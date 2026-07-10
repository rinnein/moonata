# JSONata 官方测试集实现 Workflow

本文档定义 Moonata 从获取 `jsonata-js/jsonata` 官方测试集，到审计差异、实现修复、沉淀回归测试和更新完成度快照的标准流程。目标是让每一轮兼容性推进都可复跑、可定位、可验证、可提交。

## 1. 准备上游测试集

官方测试集来自 `jsonata-js/jsonata` 仓库。不要把上游仓库或测试数据复制进本仓库，统一使用本地缓存目录：

```bash
git clone --depth 1 https://github.com/jsonata-js/jsonata.git /tmp/jsonata-upstream
```

若目录已存在，直接复用；需要更新时在 `/tmp/jsonata-upstream` 内执行上游同步。网络不可用时，不更新官方完成度数字，只保留上一次已验证快照。

关键目录：

```text
/tmp/jsonata-upstream/test/test-suite/groups
/tmp/jsonata-upstream/test/test-suite/datasets
```

## 2. 构建本地 CLI

官方测试审计通过 native CLI 执行 Moonata 表达式：

```bash
moon build cmd/main --target native
```

默认可执行文件：

```text
_build/native/debug/build/cmd/main/main.exe
```

每个官方用例转换成一次 CLI 调用：

```bash
_build/native/debug/build/cmd/main/main.exe '<expr>' --file '<tmp-json-data>'
```

本仓库提供自动审计脚本：

```bash
python3 scripts/jsonata_official_audit.py
```

脚本默认读取 `/tmp/jsonata-upstream`，默认调用 `_build/native/debug/build/cmd/main/main.exe`。如果本地路径不同，用参数覆盖：

```bash
python3 scripts/jsonata_official_audit.py \
  --upstream /path/to/jsonata \
  --exe _build/native/debug/build/cmd/main/main.exe
```

## 3. 定义可比对口径

递归读取：

```text
/tmp/jsonata-upstream/test/test-suite/groups/**/*.json
```

每个 JSON 文件通常是一个官方 case 对象；若遇到数组或映射聚合格式，审计脚本应先展开为单个 case。

纳入可比对集合的条件：

- `expr` 是字符串。
- case 包含 `result` 字段。
- `bindings` 为空或缺省。
- 不包含 `expr-file`、`timelimit`、`depth` 等需要官方 harness 特殊能力的字段。

数据来源优先级：

1. case 内联 `data`；
2. case 的 `dataset` 字段，对应 `test-suite/datasets/*.json`；
3. 无数据时使用 `null`。

跳过项只表示当前 CLI 审计无法直接比较，不代表通过或失败。当前 skip 原因使用这些分类：

- `no_result`：官方 case 不含 `result`，通常是错误断言或 harness 行为断言；
- `non-string-expr`：表达式不在 `expr` 字符串字段内，例如 `expr-file`；
- `timelimit`：需要官方超时 harness；
- `bindings`：需要外部变量绑定注入。

## 4. 执行审计并记录快照

完整审计：

```bash
python3 scripts/jsonata_official_audit.py
```

只审计一个或多个 group：

```bash
python3 scripts/jsonata_official_audit.py --group function-string
python3 scripts/jsonata_official_audit.py --group function-tomillis --group function-fromMillis
```

输出前若干失败明细：

```bash
python3 scripts/jsonata_official_audit.py --group function-tomillis --show-failures 5
```

写出机器可读 JSON 报告：

```bash
python3 scripts/jsonata_official_audit.py --json-out /tmp/moonata-jsonata-audit.json
```

用于 CI 或严格门禁时，可在存在失败时返回非零退出码：

```bash
python3 scripts/jsonata_official_audit.py --fail-on-failure
```

脚本输出以下固定信息：

```text
eligible <n> pass <n> fail <n> skip <n>
top_failures
<group> <failed-count>
...
skip_reasons
<reason> <count>
...
```

当前固定快照（2026-07-10，joins tuple stream group reduce，使用 `scripts/jsonata_official_audit.py` 审计）：

```text
eligible 1251 pass 1240 fail 11 skip 431
top_failures
parent-operator 5
joins 4
performance 1
transform 1
skip_reasons
no_result 395
non-string-expr 23
timelimit 7
bindings 6
```

本轮修复（joins tuple stream group 聚合 reduce）：
- 提交：joins 18→21 pass（7→4 fail, -3），整体 pass 1237→1240 (+3)，fail 14→11 (-3)，通过率 99.0%→99.2%
- 门禁：`moon check` 0e0w，`moon test` 198/198 passed（+1 新增 joins 回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: 新增 `access_group_aggregate_tuple_stream` 函数，处理 tuple stream 模式下的分组聚合——按 key 分组后，对每组的 frames 执行 reduce（合并绑定 + 追加 @ 值），再以 reduced 上下文求值 value-expression
  - Evaluator: `access_group_aggregate_frames` 检测 frames 是否携带 focus 绑定（tuple stream 模式），是则走新的 reduce 路径，否则走原 per-frame 求值路径
  - Evaluator: focus 步在 `has_group=true` 时，将 focus 绑定传播到 frames 但保留 `@` 为原始输入（对齐 JSONata-js `evaluateTupleStep` 语义——focus 不改变 `@`，只绑定变量）
  - Evaluator: 新增 `append_tuple_binding` 函数，实现 tuple 绑定追加（Sequence/Array/标量三种情况的合并）
  - Evaluator: reduce 阶段同时追加 `@`（frame.value），匹配 JSONata-js `reduceTupleStream` 对所有 tuple 属性（包括 `@`）的 append 语义
  - Tests: 新增 joins tuple stream group reduce 回归断言（Hugh Jones 3 Contacts 合并 + mobile 过滤）
- 已知限制：
  - joins (4): `^($e.field)` sort + tuple binding + `.{ }` 路径、`$.$#$pos[$pos<3]` tuple stream 重置、`$#$pos[][$pos<3]^($)[-1]` arrayify singleton
  - parent-operator (5): `(expr)[%.field]` 分组表达式后父级过滤、`$keys(%)` 父级键列表、`%.%` 多级父级链
  - performance (1): `$$.items[$i]` 父级引用配合位置绑定（tuple stream 架构问题）
  - transform (1): `state.tempReadings[[1..4]]` slice 展平（tuple stream）

上一轮修复（transforms Eval 步支持 + parent-operator map 展平 + Sequence Index）：
- 提交：transforms 1→1 pass（1→0 fail, -1），parent-operator 14→15 pass（6→5 fail, -1），整体 pass 1235→1237 (+2)，fail 16→14 (-2)，通过率 98.8%→99.0%
- 门禁：`moon check` 0e0w，`moon test` 197/197 passed（+2 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: `access_map_frames`（父级感知 map 求值）移除 `top_is_construct` 检查，始终展平数组结果，对齐 JSONata-js `evaluateTupleStep` 语义——tuple stream 模式下数组构造器结果不保留 `cons` 标记，元素逐个展开为 tuple
  - Evaluator: `walk_transform_single` 新增 `Eval(inner_expr)` 步支持，处理 `(expr)[N]` 等 parenthesized expression 后接索引/过滤的变换路径——求值内部表达式后继续走剩余路径步
  - Evaluator: `walk_transform_single` 新增 `(Sequence, Index(i))` 分支，支持对 `Eval` 产生的 `Sequence` 结果执行索引选择
  - Tests: 新增 parent-operator map 展平 + transforms Eval 步 2 个回归断言

上一轮修复（transforms per-item update 求值 + 递归下降匹配）：
- 提交：transforms 1→1 pass（10→1 fail, -9），整体 pass 1226→1235 (+9)，fail 25→16 (-9)，通过率 98.0%→98.8%
- 门禁：`moon check` 0e0w，`moon test` 195/195 passed（+4 新增 transforms 回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: 重写 `eval_transform`，删除"一次性求值 update_val/delete_keys 再走 step 替换"的旧实现
  - Evaluator: 新增 `walk_transform` / `walk_transform_single` / `walk_transform_recursive`，按路径步逐层在深克隆结构中定位匹配项
  - Evaluator: 新增 `apply_transform_match`，对每个终端匹配项以匹配值为当前上下文（`ctx.current()`）求值 `update_ast` 与 `delete_ast`，利用 `Json::Object(Map)` / `Json::Array(Array)` 的可变引用在原位合并 update 与移除 delete 键
  - Evaluator: `walk_transform_single` 支持 Name / Index / Wildcard / Filter / Slice 步，Array 中间步自动路径展平
  - Evaluator: `walk_transform_recursive` 处理 `**`（Recursive Wildcard）— 当前值本身也是匹配项，需将剩余路径应用到当前值，再下降到子结构
  - Evaluator: (Object, Filter) 与 (_, Filter) 按 JSONata 单例序列语义对值本身求值谓词（不再误迭代字段值）
  - Evaluator: `extract_delete_keys` 新增 `Json::Array` 分支，支持 `["k1","k2"]` 字面量数组作为 delete 表达式
  - Tests: 新增 transforms per-item update / update+delete / 递归下降+过滤 / 中间数组展平 4 个回归断言

上一轮修复（parser precedence: `~>` 与 `=` 同优先级）：
- 提交：sorting 17→18 pass（全绿），joins 18→21 pass，整体 pass 1210→1214 (+4)，fail 41→37 (-4)，通过率 96.7%→97.0%
- 门禁：`moon check` 0e0w，`moon test` 189/189 passed，`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: `PathFrame` 增加路径级变量绑定表，`#$var` 不再通过全局 `__pos__` 在后续扁平序列中重编号
  - Evaluator: 含 tuple binding 的路径与排序输入切换到 frame 求值，排序后继续保留 `$o`/`$pos` 等来源绑定
  - Evaluator: frame 模式下补齐序列级 Index/Slice，避免 `$#$pos[$pos<3][1]` 被错误解释为逐 frame 索引
  - Tests: 增加官方 sorting case020 与 joins/index 位置绑定等价回归断言

本轮修复（谓词过滤后 `[0]` 索引逐元素语义：Name→Filter→Index 路径分组，保留 per-element 数组结构）：
- 提交：predicates 1→2 pass（全绿），整体 pass 1210→1210，fail 41→41，通过率 96.7%
- 门禁：`moon check` 0e0w，`moon test` 187/187 passed，`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: `eval_path_from` 新增 Name→Filter→Index 分组检测，使用 `access_field_grouped` 保留数组结构，`access_filter_grouped` 逐元素过滤，后续 Index 步通过 `access_grouped` 逐元素索引
  - Evaluator: `access_filter_grouped` 新函数，对 Sequence 中每个元素独立应用 filter，保留数组结构
  - Tests: 增加官方 predicates case003 等价回归断言（`Product[$filter][0].Price` 返回每个 Order 的逐元素结果）

本轮修复（lambdas 递归函数可见性：用户定义 lambda 缺少参数时不再部分应用，改为传入 undefined）：
- 提交：lambdas 11→12 pass（全绿），整体 pass 1209→1210 (+1)，fail 42→41 (-1)，通过率 96.6%→96.7%
- 门禁：`moon check` 0e0w，`moon test` 185/185 passed，`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: `should_partial_on_missing` 对 signature 为 None 的用户自定义 lambda 返回 false，不再自动部分应用，改为传入 undefined 参数，使递归 lambda 能正确调用自身
  - Tests: 增加官方 lambdas case010 等价回归断言（`$range` 递归调用）

本轮修复（`[]` 空数组选择器语义对齐 + 分组聚合 per-group 求值 + 合并值展平）：
- 提交：flattening 4→0 pass（全绿），object-constructor 2→0 pass（全绿），boolean-expresssions 1→0 pass（全绿），整体 pass 1202→1209 (+7)，fail 49→42 (-7)，通过率 96.0%→96.6%
- 门禁：`moon check` 0e0w，`moon test` 183/183 passed，`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: `[]`（Arrayify 步）改为路径求值中的 no-op 标记，阻止最终值的单例提升；`arrayify_wrap` 在路径末尾将结果包装为 `Json::Array`
  - Evaluator: `eval_path` 新增 `steps_has_arrayify` 检查和 `arrayify_wrap` 函数，`eval_step_frame_single` 中 Arrayify 步改为 no-op
  - Evaluator: `access_group_aggregate` 改为 per-group 求值（先按 key 分组合并输入项，再对每组求值 value-expression），匹配 JSONata-js `evaluateGroupExpression` 语义
  - Evaluator: `json_for_merged_values` 新增 `all_are_json_arrays` 分支，全数组值时展平为单个数组（如 `[[1], [2]]` → `[1, 2]`）
  - Tests: 增加官方 flattening case037/case038/case041/case043 等价回归断言

本轮修复（URL 百分号编码/解码函数）：
- 提交：function-decodeUrl 0→1 pass（全绿），function-encodeUrl 0→1 pass（全绿），function-decodeUrlComponent 0→1 pass（全绿），function-encodeUrlComponent 0→1 pass（全绿），整体 pass 1189→1193 (+4)，fail 62→58 (-4)，通过率 95.0%→95.4%
- 门禁：`moon check` 0e0w，`moon test` 183/183 passed，`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Functions: 新增 `$encodeUrl` / `$decodeUrl` / `$encodeUrlComponent` / `$decodeUrlComponent` 四个百分号编码/解码函数
  - Functions: `$encodeUrl` 保留 URL 保留字符 `:/?#[]@!$&'()*+,;=`，`$encodeUrlComponent` 不保留任何保留字符
  - Functions: `$decodeUrl` / `$decodeUrlComponent` 将 `%XX` 序列还原为 UTF-8 字符串
  - Functions: 百分号编码使用 UTF-8 字节序列编码，支持非 ASCII 字符
  - Tests: 增加官方 function-decodeUrl/function-encodeUrl/function-decodeUrlComponent/function-encodeUrlComponent case000 等价回归断言

本轮修复（variables 链式赋值与块级作用域）：
- 提交：variables 1→6 pass（全绿），整体 pass 1184→1189 (+5)，fail 67→62 (-5)，通过率 94.6%→95.0%
- 门禁：`moon check` 0e0w，`moon test` 182/182 passed，`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - AST: `Bind` 从 `(name, value, body)` 三元节点变为 `(name, value)` 二元节点，`:=` 作为赋值表达式返回赋值的值
  - Parser: `parse_bind` 不再吞掉分号和 body，`;` 由上层 `parse_block` 自然消费，支持 `$a := $b := 5` 链式赋值
  - Parser: 括号表达式 `(...)` 永远包裹在 `Block` 中，为顶层单表达式绑定提供块级作用域
  - Evaluator: `eval_bind` 使用 `ctx.bind` 持久绑定并返回赋值结果；`eval_block` 在块结束时恢复绑定快照，实现块级作用域
  - Value: EvalContext 增加 `bindings_snapshot`/`restore_bindings` 方法
  - Tests: 增加官方 variables case004/case005/case006/case007/case010 等价回归断言

本轮修复（parent-operator 父级链路）：
- 提交：parent-operator 0→14 pass，整体 pass 1170→1184 (+14)，fail 81→67 (-14)，通过率 93.5%→94.6%
- 门禁：`moon check` 0e0w，`moon test` 182/182 passed，`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Value: `EvalContext` 记录父级链，支持 `%` 与 `%.%` 读取直接父级和祖先级上下文
  - Evaluator: 含 `%` 的路径使用父级感知帧求值，在字段展开、map、filter、group 和 sort 中保留每项来源上下文
  - Tests: 增加 parent-operator 等价回归断言，覆盖 map、filter 与 Description→Product→Order 祖先链

本轮修复（简单数组选择器逐项索引）：
- 提交：simple-array-selectors 20→23 pass（全绿），flattening 失败 7→4，总体 pass 1164→1170 (+6)，fail 87→81 (-6)，通过率 93.0%→93.5%
- 门禁：`moon check` 0e0w，`moon test` 182/182 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Evaluator: 分组字段访问在 Sequence 输入上推回字段求值结果，而不是原始 item
  - Evaluator: 分组 Index/Slice 在 Sequence 输入上推回逐项索引结果，恢复 `a.b[0]` / `foo.bar[-1]` 逐项选择语义
  - Tests: 增加官方 simple-array-selectors case000/case005/case006 等价回归断言

本轮修复（多索引数组选择器）：
- 提交：multiple-array-selectors 1→3 pass（全绿），joins 失败 13→10，总体 pass 1158→1164 (+6)，fail 93→87 (-6)，通过率 92.6%→93.0%
- 门禁：`moon check` 0e0w，`moon test` 181/181 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Evaluator: 谓词过滤支持纯数字数组/序列作为多索引选择器，并复用负索引归一化
  - Evaluator: 混入非数字值的数组谓词退回原 truthy 行为，避免把 `[1..3,8,false]` 错当索引列表
  - Tests: 增加官方 multiple-array-selectors case000/case001/case002 等价回归断言

本轮修复（`$spread` 对象序列）：
- 提交：function-spread 1→3 pass（全绿），总体 pass 1156→1158 (+2)，fail 95→93 (-2)，通过率 92.4%→92.6%
- 门禁：`moon check` 0e0w，`moon test` 180/180 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Functions: `$spread` 对非对象输入按原值返回，兼容 `$spread("Hello World")`
  - Functions: `$spread` 支持对象数组/序列，按每个对象的字段顺序展开为单键对象序列
  - Tests: 增加官方 function-spread case000/case001 等价回归断言

本轮修复（`$sift` predicate 与递归通配去重）：
- 提交：function-sift 3→5 pass（全绿），descendent-operator 14→15 pass（全绿），总体 pass 1153→1156 (+3)，fail 98→95 (-3)，通过率 92.2%→92.4%
- 门禁：`moon check` 0e0w，`moon test` 178/178 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Functions: `$sift` predicate 传入 `(value, key, object)`，并在过滤结果为空时返回 Undefined，使路径映射自然省略空对象
  - Evaluator: 递归 wildcard 保留当前结构节点，并对递归通配结果做唯一化，避免 `**.*` 后续路径重复访问同一结构
  - Tests: 增加官方 function-sift case001/case004 等价回归断言

本轮修复（`$reverse` 与数组构造展开）：
- 提交：function-reverse 1→3 pass（全绿），flattening 失败 11→7，总体 pass 1146→1153 (+7)，fail 105→98 (-7)，通过率 91.6%→92.2%
- 门禁：`moon check` 0e0w，`moon test` 176/176 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Functions: `$reverse` 返回显式 JSON array，单元素数组不再被序列提升为标量
  - Evaluator: 数组构造中非显式构造表达式求得的 JSON array 按元素展开，保留显式嵌套数组构造
  - Tests: 增加官方 function-reverse case001/case003 等价回归断言

本轮修复（`$keys` 对象序列）：
- 提交：function-keys 1→3 pass（全绿），总体 pass 1144→1146 (+2)，fail 107→105 (-2)，通过率 91.4%→91.6%
- 门禁：`moon check` 0e0w，`moon test` 176/176 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Functions: `$keys` 支持对象数组/序列，按首次出现顺序汇总去重 key
  - Functions: `$keys` 返回遵循 JSONata 序列规则，单个 key 提升为字符串
  - Tests: 增加官方 function-keys case001/case003 等价回归断言

本轮修复（字符串字面量谓词过滤）：
- 提交：conditionals 5→7 pass（全绿），总体 pass 1142→1144 (+2)，fail 109→107 (-2)，通过率 91.3%→91.4%
- 门禁：`moon check` 0e0w，`moon test` 176/176 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Parser: 普通字符串字面量后接 `[]` 时保持字面量求值，不再误转为字段路径
  - Tests: 增加官方 conditionals case000/case001 等价回归断言，并覆盖 `"Red"[true]` 最小形态

本轮修复（Lambda 闭包与反引号字段名）：
- 提交：closures 0→2 pass（全绿），object-constructor 16→18 pass，joins 14→15 pass，总体 pass 1133→1142 (+9)，fail 118→109 (-9)，通过率 90.6%→91.3%
- 门禁：`moon check` 0e0w，`moon test` 176/176 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Lexer/AST/Parser: 区分反引号字段名与普通字符串字面量，表达式位置的 `` `field` `` 按当前上下文字段访问求值，路径后缀继续支持 quoted name
  - Evaluator: Lambda 捕获定义时上下文，并在调用时补齐调用点新增绑定，恢复递归与互递归函数可见性
  - Evaluator: 对象聚合中重复的相同字符串值折叠为标量，保留数值等其它重复值的数组聚合语义
  - Tests: 增加官方 closures 两个失败形态的等价回归断言，以及反引号 token 回归

本轮修复（function-fromMillis picture 与空括号）：
- 提交：function-fromMillis 85→88 pass（全绿），object-constructor 额外减少 1 fail，总体 pass 1129→1133 (+4)，fail 122→118 (-4)，通过率 90.2%→90.6%
- 门禁：`moon check` 0e0w，`moon test` 174/174 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Functions: `$fromMillis`/`$formatDateTime` 支持 `[YI]`/`[Yi]` 罗马数字年份与 `[DA]`/`[Da]`、`[MA]`/`[Ma]` 字母序 day/month marker
  - Functions: 第二个 picture 参数为 undefined 时使用默认 ISO date-time picture，并继续应用第三个 timezone 参数
  - Parser: `()` 解析为空 block，求值为 undefined，用于官方函数参数中的空 picture
  - Tests: 增加官方 function-fromMillis 剩余 3 个失败用例的等价回归断言

本轮修复（string-concat undefined 与序列字符串化）：
- 提交：string-concat 9→12 pass（全绿），总体 pass 1126→1129 (+3)，fail 125→122 (-3)，通过率 90.0%→90.2%
- 门禁：`moon check` 0e0w，`moon test` 174/174 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Evaluator: `&` 运算遇到 undefined 时不走通用传播，改为按 JSONata 字符串拼接规则处理为空字符串
  - Evaluator: 多值 `Sequence` 转字符串时输出 JSON 数组字符串，避免 `lift_singleton` 对多值序列递归回自身导致超时
  - Tests: 增加官方 string-concat case004/case005/case011 等价回归断言

本轮修复（$formatNumber zero-digit 与负数子图）：
- 提交：function-formatNumber 22→26 pass（全绿），总体 pass 1122→1126 (+4)，fail 129→125 (-4)，通过率 89.7%→90.0%
- 门禁：`moon check` 0e0w，`moon test` 174/174 passed，`moon fmt` 与 `moon info` 已执行
- 修复内容：
  - Functions: `$formatNumber` 读取 `zero-digit` option，将 picture 中同一数字族字符归一化为数字占位符，输出时再映射回目标数字族
  - Functions: `$formatNumber` 支持 `positive;negative` 子图，负数子图不再自动添加 `-`
  - Tests: 增加官方 case011/case016/case034/case035 等价回归断言

本轮修复（$map 回调参数 + chain regex + filter truthy + parser `~>` 优先级）：
- 提交：hof-map 6→0 pass (+6 但部分与 $map 共用)，function-applications 17→18 pass (+1)，总体 pass 1118→1122 (+4)，fail 133→129 (-4)，通过率 89.4%→89.7%
- 门禁：`moon check` 0e0w，`moon test` 174/174 passed，`moon info` OK
- 修复内容：
  - Functions: `$map`/`$filter` 回调参数改为 `(item, index, source_array)`（hof-map 全绿）
  - Evaluator: `eval_chain` 支持 `str ~> /regex/flags` 链式正则匹配
  - Evaluator: `access_filter` 非布尔/非数字 truthy 结果推送 `item` 而非表达式结果（修复 regex chain 在 filter 内行为）
  - Parser: `parse_chain` 将右侧末尾 `[]` 分离为链的独立阶段（`~>` 优先级低于 `[]`）

上一轮修复（路径展平 + 通配符兼容性）：
- 提交：wildcards 4→0 pass (+4), flattening 12→8 pass (+4), 总体 pass 1110→1118 (+8), fail 141→133 (-8), 通过率 88.7%→89.4%
- 门禁：`moon check` 0e0w, `moon test` 174/174 passed, `moon info` OK
- 修复内容：
  - Evaluator: `eval_path_from` 新增 `is_first_step` 标志，首步 Name→Index 在 Array/Sequence 输入不分组（fix `phone[0]`、`a[0].b`），后续步正常分组（保持 `a.b[0]` 兼容）
  - Evaluator: `access_wildcard` 使用 `push_path_result` 替代 `results.push`，内层数组正确展平
- 已知限制: `[]` 步骤后字段访问的单例提升问题（3 fail），嵌套 `.()` 展平多一层（4 fail），Group 构造内 `[]` 展平（1 fail）

上一轮修复（transforms 操作符解析基础）：
- 提交：transforms 0→1 pass (+1), 总体 pass 1109→1110 (+1), fail 142→141 (-1), 通过率 88.5%→88.7%
- 门禁：`moon check` 0e0w, `moon test` 174/174 passed, `moon info` OK
- 修复内容：
  - AST: 新增 `Transform(path, update, delete?)` 节点
  - Parser: `parse_chain` 检测 `~>` 后 `|` 进入 `parse_transform`，解析 `| path | update [, delete] |`
  - Evaluator: `eval_chain` 新增 Transform 阶段处理，`eval_transform` 深克隆 + 路径替换基础实现
  - 已知限制: update 模板在全量上下文求值而非 per-item（导致 multi-level path + array 变换不生效），`nomatch`/`**` 模式未实现

每次更新快照时，同步记录：

- 日期；
- 当前提交；
- `moon check` / `moon test` / `moon info` 结果；
- 官方审计统计；
- 失败最多的前 10 个 group；
- skip 原因计数；
- 本轮修复涉及的官方 group 和本地测试增量。

## 5. 选择修复阶段

每一轮只选择一个小而清晰的失败面，优先顺序如下：

1. 失败数最高且语义边界清楚的官方 group；
2. 能通过少量 parser/evaluator/functions 改动覆盖多个 group 的共享缺口；
3. 已经有本地基础能力，只需对齐边界行为的函数；
4. 不需要大规模重构或未决设计决策的用例。

不要在同一轮混合多个互不相关的语义主题。推荐阶段粒度示例：

- 日期解析与格式化：`function-tomillis`、`function-fromMillis`；
- 数字格式化：`function-formatNumber`、`function-formatInteger`；
- 上下文和 parent 语义：`parent-operator`、`joins`；
- 序列展平：`flattening`、路径相关 group；
- 对象构造与排序：`object-constructor`、`sorting`。

## 6. 定位差异

定位一个失败 group 时，按以下顺序收集证据：

1. 读取官方 case 的 `expr`、`data`/`dataset`、`result`；
2. 用 `scripts/jsonata_official_audit.py --group <group> --show-failures <n>` 获取失败 case；
3. 用本地 CLI 单独执行该表达式；
4. 判断失败类型：解析失败、运行时错误、输出 JSON 不一致、超时；
5. 若是解析失败，优先检查 `lexer/` 与 `parser/`；
6. 若是输出不一致，优先检查 `evaluator/`、`value/`、`functions/`；
7. 若多个 group 同时失败，先找共享语义，而不是逐个硬编码 case。

修复前应把至少一个最小复现沉淀为本地测试。能稳定表达官方语义的用例使用 `assert_eq`；结构化调试或 AST 输出才使用快照。

## 7. 实现修复

实现时遵循包边界：

- 词法问题改 `lexer/`；
- 语法结构问题改 `parser/` 与 `ast/`；
- JSONata 序列、上下文、路径、运算符问题改 `value/` 与 `evaluator/`；
- 内建函数行为改 `functions/`；
- CLI 输入输出或审计入口问题改 `cmd/main/`；
- facade 行为改根包 `moonata.mbt`。

修复原则：

- 优先实现 JSONata 语义，不为单个官方 case 写特判；
- 对公开 API 变更同步运行 `moon info` 并检查 `.mbti`；
- 对错误类型保持 `JsonataError` 统一出口；
- 对可能引入循环或爆炸求值的逻辑保留 `EvalContext` 护栏；
- 对日期、正则、Unicode 等库相关行为，明确记录 MoonBit 库能力和差异。

## 8. 沉淀本地回归测试

每个修复阶段至少补充以下测试之一：

- 官方表达式的最小等价用例；
- 对应函数的边界行为；
- parser/evaluator 的共享语义断言；
- CLI 端到端冒烟用例。

测试文件优先放在受影响包附近；跨包行为和官方兼容性用例放在 `moonata_test.mbt`。

## 9. 本地门禁

每轮修复完成后执行：

```bash
moon fmt
moon check
moon test
moon info
```

若涉及 native CLI，再执行：

```bash
moon build cmd/main --target native
```

所有本地门禁通过后，才允许更新官方快照和提交。

## 10. 复跑官方审计

本地门禁通过后，复跑官方可比对审计：

```bash
python3 scripts/jsonata_official_audit.py --json-out /tmp/moonata-jsonata-audit.json
```

比较新旧快照：

- `pass` 必须增加，或失败原因被明确重新分类；
- `fail` 不应在无解释情况下增加；
- `skip` 只应因审计口径变化而变化；
- 若引入回退，必须先修复或记录为已知风险，不能直接提交。

本轮修复完成后，在以下文件中同步最新快照：

- `docs/jsonata-official-workflow.md`（本文档，节 4 中的固定快照块）
- `docs/development-plan.md`
- `.codebuddy/rules/moonata_项目实现指南.mdc`
- `README.md` 兼容性状态一栏（pass/fail/skip、通过率、top failures）

## 11. 提交节奏

每个阶段提交应是可验证里程碑，提交信息使用约定式格式。**同一个阶段的所有变更（代码 + 快照 + README）合并为一个 commit**，不拆分：

```text
fix(functions): align formatNumber scientific notation, +12 pass

- format_scientific: implement e/E scientific notation formatting
- leading_number_prefix: extract prefix to avoid false E matches
- format_number_integer_from_double: avoid Int64 overflow for large numbers

Snapshot: eligible 1251 pass 1109 fail 142 skip 431 (88.6%)
```

提交前确认：

- 本地门禁全绿；
- 官方审计快照已更新（`docs/jsonata-official-workflow.md`、`.codebuddy/rules/moonata_项目实现指南.mdc`）；
- `README.md` 兼容性状态一栏已同步更新（pass/fail/skip、通过率、top failures）；
- **快照更新与 README 更新必须与程序变更在同一个 commit 中提交**，禁止拆分为独立的 "docs: update snapshot" 提交；
- 本地回归测试覆盖本轮修复；
- 文档记录了剩余失败最多的 group；
- 没有把 `/tmp/jsonata-upstream` 或临时审计数据加入仓库。

## 12. 暂停与恢复

暂停时必须固定当前状态：

- 最新提交；
- 本地测试数量；
- 官方 `eligible/pass/fail/skip`；
- top failures；
- skip reasons；
- 下一轮建议入口。

恢复时先复跑 native CLI 构建和官方审计，确认数字与文档一致；若不一致，先解释差异，再开始修复。
