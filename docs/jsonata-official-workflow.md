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

当前固定快照（2026-07-07，简单数组选择器逐项索引修复，使用 `scripts/jsonata_official_audit.py` 审计）：

```text
eligible 1251 pass 1170 fail 81 skip 431
top_failures
parent-operator 20
function-tomillis 10
joins 10
transforms 10
variables 5
flattening 4
function-applications 2
object-constructor 2
transform 2
boolean-expresssions 1
skip_reasons
no_result 395
non-string-expr 23
timelimit 7
bindings 6
```

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
