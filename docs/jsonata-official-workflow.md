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

- `expr` 是字符串，或可以通过 `expr-file` 解析到外部表达式文件。
- 期望值可以是 `result`、`undefinedResult` 或 `code`。
- `bindings` 会被脚本注入为本地绑定块；当前仅对可 JSON 化的绑定值做可比较处理。
- `timelimit` 会按 case 级超时处理，不再直接视为不可比。
- `depth` 仍然属于官方 harness 能力，暂不在脚本层模拟。

数据来源优先级：

1. case 内联 `data`；
2. case 的 `dataset` 字段，对应 `test-suite/datasets/*.json`；
3. 无数据时使用 `null`。

跳过项只表示当前 CLI 审计无法直接比较，不代表通过或失败。当前 skip 原因使用这些分类：

- `no_expected_outcome`：官方 case 没有 `result` / `undefinedResult` / `code`，通常是 harness 行为断言；
- `non-string-expr`：`expr` 不是字符串，且 `expr-file` 也无法解析；
- `missing-file`：`expr-file` 指向的外部表达式文件不存在；
- `missing-dataset`：`dataset` 无法解析到本地数据文件；
- `invalid-binding-name`：`bindings` 中出现无法安全注入的变量名；
- `depth`：需要官方深度限制 harness。

说明：`code` 类期望值会先与当前 CLI 的错误文本做包含匹配，因此只要错误消息里保留了官方代码前缀，脚本就可以直接参与比较。

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

下方固定快照仍是旧口径下的历史记录；本轮脚本升级后，`skip` 分类会更细，待下一次复跑官方审计后再刷新这里的数字。


当前固定快照（2026-07-15，TCO 尾调用优化 + depth 下沉到 eval 入口 + --max-depth CLI 标志，使用 `scripts/jsonata_official_audit.py` 审计）：

```text
eligible 1667 pass 1667 fail 0 skip 15
top_failures
skip_reasons
no_expected_outcome 15
```

本轮修复（TCO 尾调用优化 + depth 下沉到 eval 入口 + --max-depth CLI 标志）：
- 提交：整体 pass 1666→1667 (+1)，fail 1→0 (-1)，通过率 99.94%→100%
- 门禁：`moon check` 0e0w，`moon test` 291/291 passed，`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - AST: `Lambda` 新增 `thunk~ : Bool` 字段，标记尾调用 thunk Lambda
  - Parser: 新增 `tail_call_optimize` 后处理，对齐 jsonata-js `tailCallOptimize`——将 Lambda body 中的尾位置函数调用（Apply）包装为 `Lambda(thunk=true, body=Apply(...))`，对 Conditional 的 then/else 分支与 Block 的最后一个表达式递归处理
  - Value: `JsonataFunc` 新增 `thunk_call` 字段（闭包返回下一个 (func, args)）；新增 `JsonataFunc::apply` 方法实现 trampoline 循环——调用 `invoke` 后若返回 thunk Func 则循环展开，对齐 jsonata-js `apply()` + `applyInner` 的 `validateArguments` 调用；trampoline 迭代上限 10000 拦截无限尾递归（case006）
  - Value: `EvalContext::tick` 步数超限改抛 U1001（对齐 jsonata-js timeboxExpression 超时语义）；`default_max_steps` 保持 1000000 覆盖复杂表达式
  - Evaluator: `eval` 入口新增 `ctx.enter()`/`ctx.exit()` depth 管理（对齐 jsonata-js `evaluate()` 的 `environment.base.depth++`），使 `tail-recursion/case002`（factorial(100)，非尾递归）在 max_depth=302 下触发 U1001；移除所有 `with_depth` 调用（已由 eval 入口统一管理）
  - Evaluator: `eval_apply`/`eval_chain`/`compose_functions` 等通过 `apply_with_trampoline` → `JsonataFunc::apply` 调用函数，确保尾递归经 trampoline 展开不增长调用栈
  - Functions: `$map`/`$filter`/`$reduce`/`$sift`/`$sort`/`$match`/`$split` 等 HOF 的回调调用从 `(f.invoke)(args, ctx)` 改为 `f.apply(args, ctx)`，确保 lambda body 经 TCO 包装后返回的 thunk Func 被正确展开
  - CLI: `cmd/main` 新增 `--max-depth` 标志，对齐 jsonata-js test runner 的 `timeboxExpression` maxDepth 语义
  - Audit: `scripts/jsonata_official_audit.py` 从 case 文件的 `depth` 字段传递 `--max-depth` 给 CLI，使 `tail-recursion/case002`（depth=302）等用例能在指定深度触发 U1001
  - moonata: 新增 `evaluate_with_max_depth`/`evaluate_undefined_with_max_depth` facade API
- 修复效果：`tail-recursion` group 9→10 pass（全绿，-1 fail），`tail-recursion/case002` 由 mismatch → pass（U1001 在 max_depth=302 下触发），整体 fail 1→0
- 关键设计决策：
  - jsonata-js 通过 `__evaluate_entry` 回调在每次 `evaluate()` 入口递增 depth；本实现对齐此语义，将 depth 管理从 `with_depth` 调用点下沉到 `eval` 入口
  - jsonata-js 通过 `tailCallOptimize` + thunk + trampoline 实现尾调用优化，使尾递归不增长调用栈；本实现完整移植此机制，使 `case007`（6555 层互递归）在 max_depth=500 下完成
  - 无限尾递归（case006 `$inf()`）在 jsonata-js 中通过 timeout 触发 U1001；本实现通过 trampoline 迭代上限（10000）在 timelimit 内触发 U1001

上一轮修复（Object 变体保留函数字段 + $match matcher 协议 + lambda letrec 自引用）：
- 提交：整体 pass 1665→1666 (+1)，fail 2→1 (-1)，通过率 99.9%→99.94%
- 门禁：`moon check` 0e0w，`moon test` 290→291 passed（+1 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Value: `JsonataValue` 新增 `Object(Map[String, JsonataValue])` 变体，保留对象字面量中的函数/正则字段（不被 `json_for_constructor` 序列化为空字符串）；`to_json`/`equal`/`is_undefined` 等核心方法同步处理新变体
  - Evaluator: `eval_group` 在对象字面量含 Func/Regex 字段时返回 `Object` 变体（否则回退 `Json::object` 保持向后兼容）；路径访问（`access_field`/`access_field_frames`/`access_field_grouped`/`access_wildcard` 等）新增 `Object` 分支，返回字段原始 `JsonataValue`（含 Func），使函数字段可被后续路径访问与调用
  - Evaluator: `eval_bind` 对 Lambda 值启用 letrec 语义——新增 `eval_lambda_recursive` 函数，invoke 时绑定 `self_name` 到函数自身，修复递归 lambda 跨函数返回后丢失自引用的问题（matcher 协议中 `next` 调用 `$match` 递归的场景）
  - Functions: `$match` 新增函数 matcher 支持（`match_with_matcher`），对齐 jsonata-js `evaluateMatcher`——调用 matcher(str, 0) → 通过对象 `next` 字段迭代收集所有匹配 → 转换为 `{match, index, groups}` 输出格式
  - Functions: `$split` 的 `split_with_matcher` 重写为迭代分割（通过 `next` 函数获取后续匹配），替代之前仅识别首个匹配的限制；新增 `extract_match_info` 辅助函数支持 `Object` 与 `Json::Object` 两种表示
  - Functions: `validate_matcher_result` 新增 `Object` 变体分支，可直接识别 `next` 字段为 Func（`Json::Object` 分支因函数已序列化仍用宽松判定）
  - Tests: 新增 matchers case000 回归断言（`$match("abracadabra", $generateMatcher('a'))` 返回 5 个 `{match, index, groups}` 匹配）
- 修复效果：`matchers/case000` 由 mismatch → pass（`$match` 函数 matcher 协议完整实现，`next` 函数可迭代调用）
- 剩余重点：
  - `tail-recursion/case002`：`$factorial(100)` 期望 U1001（jsonata-js test runner 设 `maxDepth=302`，jsonata-js 每次进入 `evaluate()` 即递增 depth，100 层 factorial 累计 ~300+ 次 evaluate 调用）；本实现 `depth` 仅在 `with_depth` 调用点递增（函数 invoke / 谓词 / 路径步等），100 层 factorial 仅累积 ~100 depth，远低于 `max_depth=8000`；修复需将 depth 计数下沉到 `eval` 入口，影响面较大，留待后续轮次

上一轮修复（dataset:null → undefined 语义对齐 + $join/$split/$map 严格签名校验）：
- 提交：整体 pass 1664→1665 (+1)，fail 3→2 (-1)，通过率 99.8%→99.9%
- 门禁：`moon check` 0e0w，`moon test` 286→290 passed（+4 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Audit: `scripts/jsonata_official_audit.py` 的 `data_for` 返回 `use_undefined` 标志，当 case 无内联 `data` 且 `dataset` 为 `null` 或缺失时设为 `True`，对齐 jsonata-js `run-test-suite.js#resolveDataset` 中 `dataset === null → undefined` 的语义；`run_case` 在 `use_undefined=True` 时调用 CLI `--no-data` 标志（替代写 `null` 到临时文件），使根上下文为 `Undefined` 而非 `Json::Null`
  - Functions: `$join` 启用复杂签名 `a<s>s?` 并关闭 `contextual`，对齐 jsonata-js `<a<s>s?:s>`——0 参调用（无论上下文是否定义）由 `validate_args` 抛 T0410，而非 `apply_context_argument` 前置上下文后 silent 返回 undefined；删除冗余的 null/类型手工校验，保留 T0412 字符串元素校验
  - Functions: `$split` 启用复杂签名 `s-(sf)n?` 并关闭 `contextual`，对齐 jsonata-js `<s-(sf)n?:a<s>>`——`$split(12345)` 等首参非字符串场景由签名校验抛 T0410，而非前置上下文导致用户实参偏移到 separator 位置后 silent 返回 undefined；保留 D3020 负 limit 与 matcher 协议路径
  - Functions: `$split_regex` 的 limit 判定从 `args.length() > 2` 改为 `args.length() > 2 && !args[2].is_undefined()`，因为复杂签名会为可选参数 `n?` 自动补齐 `Undefined`，原判定会误把 Undefined 当作 `value_to_int → 0` 触发空数组返回
  - Functions: `$map` 关闭 `contextual`（保留签名 `af`），对齐 jsonata-js `<af>`——`$map($add)` 单参调用由签名校验抛 T0410，而非前置上下文后进入函数体；2 参调用与 `~>` 链式调用行为不变
  - Tests: 新增 4 个回归断言——`$string()` undefined 上下文返回 undefined、`$join()`/`$split(12345)`/`$map($add)` undefined 上下文抛 T0410
- 修复效果：`function-string/case022` 由 mismatch → pass（`$string()` + undefined 上下文返回 undefined），`function-join/case011`、`function-split/case017`、`hof-map/case001` 由 silent undefined → T0410 pass；本轮 audit 脚本语义对齐 jsonata-js 后这三个 case 不再"虚假通过"
- 剩余重点：
  - `matchers/case000`：`$match(str, matcherFn)` 期望通过 matcher 协议迭代返回多匹配数组；当前对象构造器无法保留函数值字段（`{next: function(){...}}` 中的 `next` 会被 `json_for_constructor` 序列化为空字符串），导致无法从匹配对象还原 `next` 句柄迭代；修复需扩展对象构造器以保留 `JsonataValue::Func` 字段，留待后续轮次
  - `tail-recursion/case002`：`$factorial(100)` 期望 U1001（jsonata-js test runner 设 `maxDepth=302`，jsonata-js 每次进入 `evaluate()` 即递增 depth，100 层 factorial 累计 ~300+ 次 evaluate 调用）；本实现 `depth` 仅在 `with_depth` 调用点递增（函数 invoke / 谓词 / 路径步等），100 层 factorial 仅累积 ~100 depth，远低于 `max_depth=8000`；修复需将 depth 计数下沉到 `eval` 入口，影响面较大，留待后续轮次

上一轮修复（matchers T1010 + tail-recursion U1001 + Lambda depth propagation）：
- 提交：整体 pass 1661→1664 (+3)，fail 6→3 (-3)，通过率 99.6%→99.8%
- 门禁：`moon check` 0e0w，`moon test` 285→286 passed（+1 新增回归断言；U1001/互递归 case007 通过 native CLI 审计脚本验证，WASM 栈深不足故不在 moon test 中直接断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Value: `EvalContext::enter` 抛出的 `GuardrailError` 携带 `code=Some("U1001")`，对齐 jsonata-js 栈溢出错误码（`D1011` 在 jsonata-js 中是可选 stack 限制的错误码，官方测试集 `tail-recursion` group 通过 `timeboxExpression` 设置 `maxDepth` 后改抛 `U1001`）
  - Value: `default_max_depth` 从 1000 提升到 8000，覆盖 `tail-recursion/case007` 的 6555 层互递归；同时足够低以在 8MB native 栈耗尽前拦截无限递归
  - Value: 新增 `EvalContext::sync_depth_from(other)` 方法，用于跨上下文同步递归深度计数
  - Evaluator: `eval_lambda` invoke 中将 caller 的 `depth` 同步到 `call_ctx`（替代原来从 `captured_ctx.depth` 起算），修复递归调用永远不超过 `max_depth` 的护栏失效问题——这是 `tail-recursion/case005` 与 `case006` 之前以 SIGSEGV (exit -11) 退出而非抛 U1001 的根因
  - Functions: `$split` 在 separator 为函数时走 matcher 协议，新增 `validate_matcher_result` 校验返回值结构（必须是 undefined 或包含 `start`/`end`/`groups`/`next` 至少其一的对象），否则抛 `T1010`，对齐 jsonata-js `evaluateMatcher`；新增 `split_with_matcher` 实现单匹配分割路径
  - Tests: 新增 matchers T1010 回归断言（`$split('some text', $uppercase)` 抛 T1010）
- 修复效果：`matchers` group 0→1 pass（-1 fail），`tail-recursion` group 7→9 pass（-2 fail，case005/case006 现抛 U1001 而非 segfault；case007 互递归 6555 层正常返回 true）
- 剩余重点：
  - `function-string/case022`：`$string()` + `dataset: null` 期望 undefined，本仓库 CLI 当前把 `dataset: null` 解析为 `Json::null()` 上下文，与 jsonata-js test runner 将其映射为 `undefined` 的语义不一致；修复需调整审计脚本对 `dataset: null` 使用 `--no-data` 标志，但会连带影响 $join/$split/$map 等函数对 0 参时 undefined 上下文的签名校验路径，留待后续轮次
  - `matchers/case000`：`$match(str, matcherFn)` 期望通过 matcher 协议迭代返回多匹配数组；当前对象构造器无法保留函数值字段（`{next: function(){...}}` 中的 `next` 会被 `json_for_constructor` 序列化为空字符串），导致无法从匹配对象还原 `next` 句柄迭代；修复需扩展对象构造器以保留 `JsonataValue::Func` 字段，留待后续轮次
  - `tail-recursion/case002`：`$factorial(100)` 期望 U1001（jsonata-js test runner 设 `maxDepth=302`，jsonata-js 每次进入 `evaluate()` 即递增 depth，100 层 factorial 累计 ~300+ 次 evaluate 调用）；本实现 `depth` 仅在 `with_depth` 调用点递增（函数 invoke / 谓词 / 路径步等），100 层 factorial 仅累积 ~100 depth，远低于 `max_depth=8000`；修复需将 depth 计数下沉到 `eval` 入口，影响面较大，留待后续轮次

上一轮修复（object-constructor T1003/D1009 + variables S0212 + $sum T0410 + $toMillis D3136 gap detection）：
- 提交：整体 pass 1653→1661 (+8)，fail 14→6 (-8)，通过率 99.2%→99.6%
- 门禁：`moon check` 0e0w，`moon test` 278→285 passed（+7 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: `eval_group`（standalone `{...}`）校验 key 必须为字符串（非字符串且非 undefined 抛 T1003），同一 key 被不同 pair 表达式产生抛 D1009，对齐 jsonata-js `evaluateGroupExpression`
  - Evaluator: `access_group_aggregate`（`foo{...}` 无前置 `.`）同步加入 T1003（非字符串 key）与 D1009（跨 item 共享 groups 字典，不同 pair 产生同 key）校验
  - Parser: `parse_bind` 在 `parse_conditional` 返回后检测残留的 `:=` token，非变量表达式后的 `:=` 抛 S0212（对齐 jsonata-js parser 的 infix `:=` LHS 类型检查），修复 `$a[1]:=3` 被错误抛 S0202 的问题
  - Functions: `$sum` 启用复杂签名 `a<n>:n` 并关闭 contextual，让 `validate_args` 对 0 参抛 T0410（对齐 jsonata-js `<a<n>:n>` 签名），非数字数组元素仍抛 T0412
  - Functions: `parse_date_picture_with_now` 的 D3136 间隔检测重写为 jsonata-js 的 startSpecified/endSpecified 扫描算法（按 Y M D H m s f 显著性顺序逐项扫描，指定项后遇未指定项标记 endSpecified，之后再遇指定项则抛 D3136），修复 `[M]-[D] [m]:[s]` 等缺 H 间隔的 picture
  - Tests: 新增 T1003(数字 key)/T1003(数组 key)/D1009(同 pair)/D1009(per-item)/S0212/T0410/D3136 共 7 个回归断言
- 修复效果：`object-constructor` group 22→27 pass（全绿，-5 fail），`function-sum` group 6→7 pass（全绿，-1 fail），`function-tomillis` group 59→60 pass（全绿，-1 fail），`variables` group 12→13 pass（全绿，-1 fail）
- 剩余重点：`tail-recursion` 3（U1001 栈溢出检测）、`matchers` 2（T1010 matcher 函数结构校验 + 复杂闭包）、`function-string` 1（`$string()` + `dataset: null` 需区分 undefined vs null 上下文）

上一轮修复（transforms T2011/T2012 + token S0201/S0213 + hof T0410/D3050 + partial-app T1007/T1008 + sort 单例提升，+13 pass）：
- 提交：整体 pass 1640→1653 (+13)，fail 27→14 (-13)，通过率 98.4%→99.2%
- 门禁：`moon check` 0e0w，`moon test` 271→278 passed（+7 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: `apply_transform_match` 校验 update 必须为 Object（非 undefined 时抛 T2011），`extract_delete_keys` 校验 delete 必须为 String/String-Array（非 undefined 时抛 T2012），对齐 jsonata-js `evaluateTransformExpression`
  - Parser: `.` 后跟 Number/Boolean/Null 时，若后续无 token 抛 S0213（字面量不能作为路径步），若后续有非路径 token 抛 S0201（意外的尾部 token），对齐 jsonata-js processAST 的 S0213 检查与顶层 S0201 残留 token 检查
  - Functions: `$map` 启用复杂签名 `af`，首参非 array 抛 T0410（hof-map/case001）；contextual 行为保留以兼容 1 参调用
  - Functions: `$reduce` 新增 D3050 校验（回调 arity<2 抛 D3050），并按回调 arity 注入 index（arity>=3）与 source array（arity>=4），对齐 jsonata-js foldLeft + hofFuncArgs
  - Functions: `$string` 允许 3 参（HOF 回调 (item, index, source)），超过 3 参抛 T0410；args.length==3 时跳过 args[1] 的布尔校验
  - Evaluator: `compare_op` 在比较前先 `lift_singleton`，修复 `$a.(Price * Quantity) > $b.(Price * Quantity)` 等单元素序列参与比较时抛 T2010 的问题
  - Evaluator: 偏应用 `?` 调用未定义函数时分情况：已知函数名（建议补 `$`）抛 T1007，完全未知名抛 T1008；普通调用保留 T1005/T1006
  - Tests: 新增 T2011/T2012/S0201/S0213/D3050/T0410/T1007/T1008 共 7 个回归断言（含 `eval_fn_catch`/`error_has_code` 复用）
- 修复效果：`transforms` group 12→15 pass（全绿，-3 fail），`token-conversion` 2→4 pass（全绿，-2 fail），`hof-map` 10→12 pass（全绿，-2 fail），`hof-reduce` 8→11 pass（全绿，-3 fail），`partial-application` 3→5 pass（全绿，-2 fail），`function-sort` 10→11 pass（-1 fail）

上一轮修复（D3012 replace 回调非字符串 + D1004 零长度匹配 + S0202 非操作数位未终止字符串 + 34 ambiguous_braces warnings）：
- 提交：整体 pass 1636→1640 (+4)，fail 31→27 (-4)，通过率 98.2%→98.4%
- 门禁：`moon check` 0e0w，`moon test` 271/271 passed（+3 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Functions: `resolve_replacement` 检查函数回调返回值必须为 String，非字符串抛 D3012（regex/case035, case036）
  - Functions: `$replace` 循环中零长度匹配导致 remaining 不推进时抛 D1004（regex/case022）
  - Lexer: `lex_string` 新增 `expect_operand` 参数，非操作数位未终止字符串抛 S0202，操作数位仍抛 S0101（errors/case009）
  - Global: 修复 34 个 `ambiguous_braces` 警告 — Map 空初始化 `{}` → `Map([])`，`Json::object({})` → `Json::empty_object()`（跨 evaluator/eval.mbt、evaluator/ops.mbt、functions/object.mbt、functions/regex.mbt、functions/type.mbt、value/context.mbt 共 6 文件）
  - Tests: 新增 D3012/D1004/S0202/S0101 共 4 个回归断言
- 修复效果：`regex` group 36→39 pass（全绿，-3 fail），`errors` group 24→25 pass（-1 fail）

上一轮修复（tuple-stream 过滤后的索引绑定）：

本轮修复（动态 eval、整数 picture、函数链与注释错误码）：
- 提交：整体 pass 1603→1614 (+11)，fail 64→53 (-11)，通过率 96.2%→96.8%
- 门禁：`moon check` 0e0w，`moon test` 268/268 passed（新增 2 个回归测试），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Lexer: 未闭合块注释抛 S0106
  - Evaluator: 函数链遇到非函数值抛 T2006
  - Functions: `$eval(nothing)` 传播 undefined；动态表达式语法/求值错误分别映射 D3120/D3121
  - Functions: `$exists()` 严格参数数量校验并附 T0410；`$boolean(2,3)` 保留 HOF 三参数回调兼容，同时拒绝普通双参数调用
  - Functions: `$formatInteger`/`$parseInteger` 校验整数 picture，非法序列抛 D3130，混用 Unicode 数字族抛 D3131
  - Parser: `@ bar` 识别为 S0211
  - Tests: 新增注释、函数链、整数 picture、动态 eval、exists/boolean 错误码回归断言
- 剩余重点：`parent-operator` 13、`joins` 9、`object-constructor` 5；`errors` 仅剩畸形引号 case009 的 S0202/S0101 边界差异

本轮修复（排序类型验证 T2007/T2008 + $sort D3070）：
- 提交：sorting 18→21 pass（全绿），function-sort 9→10 pass，整体 pass 1599→1603 (+4)，fail 68→64 (-4)，通过率 95.9%→96.2%
- 门禁：`moon check` 0e0w，`moon test` 266/266 passed（+4 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: 新增 `validate_sort_key_types` / `validate_sort_key_types_frames` 函数，在排序前预验证所有排序键类型一致性
  - Evaluator: 排序键为非 number/string/undefined 时抛 T2008（The sort expression doesn't evaluate to a comparable value）
  - Evaluator: 排序键混合 number 与 string 时抛 T2007（Values of different types found in the sort expression result）
  - Functions: `$sort` 自然排序新增 D3070 校验，对对象数组无比较器排序抛错
  - Functions: `$sort` 自然排序新增 `validate_natural_sort_types`，boolean/null 值抛 T2008
  - Tests: 新增 sort T2007/T2008 + $sort D3070 共 4 个回归断言
- 修复效果：`sorting` group 18→21 pass（全绿，-3 fail），`function-sort` group 9→10 pass（-1 fail）

本轮修复（字符串函数签名严格校验 + parser S0203 + 偏函数 signature 修正）：
- 提交：整体 pass 1578→1591 (+13)，fail 89→76 (-13)，通过率 94.7%→95.4%
- 门禁：`moon check` 0e0w，`moon test` 262/262 passed（+13 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Parser: `expect()` 在输入末尾抛 S0203（Expected ... before end of expression），非末尾仍抛 S0202（对齐 JSONata-js parser 的 `advance` 错误码分支）
  - Functions: `$replace` 启用复杂签名 `s(sf)(sf)n?`，严格校验参数数量与类型（T0410）；空 pattern 抛 D3010；负 limit 抛 D3011；可选 `n?` 缺省时 validate_args 追加的 Undefined 视为未提供
  - Functions: `$lowercase`/`$uppercase` 启用复杂签名 `s-` + `contextual=false`，让 `validate_args` 通过 `-` 修饰符正确处理上下文替换，参数过多抛 T0410
  - Functions: `$substringBefore`/`$substringAfter` 启用复杂签名 `s-s` + `contextual=false`，上下文类型不匹配抛 T0411（对齐 JSONata-js），参数过多/类型不匹配抛 T0410
  - Functions: `$substring` 启用复杂签名 `s-nn?` + `contextual=false`，第三参可选 `n?` 缺省时视为未提供；类型不匹配抛 T0410
  - Functions: `register` 辅助新增 `contextual` 参数（默认 `true` 保持兼容），允许按函数关闭 `apply_context_argument` 的前置上下文行为
  - Evaluator: `make_partial_apply` 将偏函数的 `signature` 设为 `None`，避免偏函数被 `validate_args` 用原始签名误校验（偏函数捕获部分参数后，原始签名已不能正确描述剩余所需参数）
  - Value: `validate_function_args`/`FunctionSignature::validate` 抛 T0410/T0411/T0412/S0401/S0402 时附带 `code=Some(...)`，使 CLI 错误输出前缀官方错误码，审计脚本能直接匹配
  - Tests: 新增 transform case057/063/069/076/084/092/094/097 + function-replace case005/008/009/010/011 共 13 个回归断言
- 修复效果：`transform` group 96→104 pass（全绿，-8 fail），`function-replace` group 7→12 pass（全绿，-5 fail）

上一轮修复（词法错误码 S0102-S0104 + date picture D3133-D3135）：
- 提交：整体 pass 1564→1571 (+7)，fail 103→96 (-7)，通过率 93.9%→94.2%
- 门禁：`moon check` 0e0w，`moon test` 242/242 passed（+6 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Lexer: `lex_number` 检测 Infinity/NaN → S0102（数字溢出），对齐 JSONata-js `isFinite` 检查
  - Lexer: `lex_string` 未知转义序列 → S0103（非法转义），对齐 JSONata-js `escapes` 检查
  - Lexer: `lex_hex4` 无效十六进制位或不足 4 位 → S0104（\u 需 4 位十六进制），对齐 JSONata-js `octets` 检查
  - Functions: `format_date_marker` 的 `[YN]` year name → D3133（N 修饰符仅适用于 M/F）
  - Functions: `format_date_marker` 的 Z marker 数字位数 >4 → D3134（时区数字过多）
  - Functions: `format_date_picture` 新增 `validate_date_picture_brackets` 预扫描，未闭合 marker → D3135（无匹配 `]`），对齐 JSONata-js 解析阶段先于格式化检查
  - Tests: 新增 literals S0102/S0103/S0104 + function-fromMillis D3133/D3134/D3135 共 6 个回归断言
- 修复效果：`literals` group 4→0（全绿），`function-fromMillis` group 3→0（全绿）

上一轮修复（比较运算 T2010/T2009 + 算术运算严格类型校验 + $single/$string 错误码）：
- 提交：整体 pass 1550→1564 (+14)，fail 117→103 (-14)，通过率 93.0%→93.9%
- 门禁：`moon check` 0e0w，`moon test` 236/236 passed（+6 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: 重写比较运算为 `compare_op` 通用入口，对齐 JSONata-js `evaluateComparisonExpression` 的 T2010（不可比较类型）→ undefined 传播 → T2009（类型不匹配）三阶段检查
  - Evaluator: 比较运算从 `eval_binary` 的 undefined 传播中排除，确保 T2010 在 undefined 传播之前检查（修复 `false > $x` 应抛 T2010 而非返回 undefined）
  - Evaluator: 算术运算从 `eval_binary` 的 undefined 传播中排除，确保 T2001/T2002 在 undefined 传播之前检查（修复 `false + $x` 应抛 T2001）
  - Evaluator: `to_number_with_code` 仅接受真正的 Number 类型（不接受字符串/布尔值），对齐 JSONata-js `isNumeric`
  - Evaluator: `to_number_with_code` 检测 Infinity → D1001，NaN → T2001/T2002
  - Evaluator: 除法以零返回 Infinity/NaN 而非报错（对齐 JSONata-js），使 `$string(1/0)` 抛 D3001
  - Functions: `$single` 0 匹配抛 D3139，>1 匹配抛 D3138（之前 0 匹配返回 undefined）
  - Functions: `$string` 第二参数非布尔抛 T0410；Infinity/NaN 直接调用抛 D3001；对象/数组嵌套 Infinity/NaN 抛 D1001
  - Tests: 新增 comparison-operators T2010/T2009、hof-single D3138/D3139、numeric-operators T2001/D1001、function-string D3001/D1001/T0410 共 6 个回归断言
- 修复效果：`comparison-operators` 4→0（全绿），`hof-single` 4→0（全绿），`numeric-operators` 4→0（全绿），`function-string` 4→1（-3）

上一轮修复（$formatNumber picture 完整校验 D3081-D3093 + undefined 传播）：
- 提交：整体 pass 1536→1550 (+14)，fail 131→117 (-14)，通过率 92.2%→93.0%
- 门禁：`moon check` 0e0w，`moon test` 230/230 passed（+6 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Functions: 重写 `validate_format_picture`，对齐 JSONata-js `validate` 的 D3081-D3093 全检查顺序与 last-error-wins 语义（后检测的错误覆盖之前的）
  - Functions: 新增 `validate_format_subpicture` 处理单个子图，计算 prefix/suffix/activePart/mantissa/exponent/integer/fraction 各部分
  - Functions: 新增 `is_format_active_char` 判定活跃字符（数字 0-9、#、.、,、;、e/E）
  - Functions: 对齐 prefix/suffix 边界——无活跃字符时 prefix="" 使 activePart 包含整个子图（修复 `%%`/`---` 等纯被动字符子图的 D3086 检测）
  - Functions: D3082/D3083 多个 %/‰、D3084 混用、D3085 mantissa 无数字、D3086 activePart 含被动字符、D3087 分组邻小数点、D3088 整数末尾分组、D3089 相邻分组、D3090/# 顺序、D3091 小数 #/数字顺序、D3092 指数含 %/‰、D3093 指数非全数字
  - Functions: `$formatNumber` 对 undefined 输入返回 undefined（对齐 JSONata-js 语义），修复 case036
  - Functions: 验证在 zero-digit 归一化后进行，使 ① 等数字族字符被正确识别为 active
  - Tests: 新增 function-formatNumber D3082/D3083/D3085/D3086/D3087/D3088/D3089/D3090/D3091/D3092/D3093 + undefined 传播共 6 个回归断言
- 修复效果：`function-formatNumber` group 14→0 fail（全绿 45/45）
- 已知限制：errors 剩余 9 个失败涉及更深层语义（留待后续轮次）

上一轮修复（JSONata 错误码系统 + range 边界严格校验）：
- 提交：整体 pass 1505→1536 (+31)，fail 162→131 (-31)，通过率 90.2%→92.2%
- 门禁：`moon check` 0e0w，`moon test` 224/224 passed（+10 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Error: 为 `JsonataError` 所有变体新增 `code~ : String?` 字段，携带 JSONata 官方错误码（如 `T2001`/`S0101`）
  - Error: 新增 `JsonataError::error_code` 方法提取错误码；便捷构造函数 `syntax_error`/`runtime_error`/`type_error`/`signature_error`/`guardrail_error` 均支持 `code?` 参数
  - CLI: 错误输出前缀官方错误码（如 `错误: T2001: TypeError(...)`），使审计脚本能通过子串匹配验证错误码
  - Evaluator: 算术运算左侧非数字抛出 `T2001`，右侧非数字抛出 `T2002`（新增 `to_number_with_code` 区分左右）
  - Evaluator: 一元负号非数字抛出 `D1002`
  - Evaluator: 调用 undefined 或非函数值抛出 `T1006`（之前 undefined 静默返回 undefined）
  - Evaluator: range 运算严格校验边界类型——非 undefined 边界必须为整数，否则抛出 `T2003`/`T2004`；仅接受真正的 Number 类型，不接受布尔值或可转数字的字符串
  - Evaluator: range 运算大小超过 1e7 抛出 `D2014`
  - Evaluator: `..` 运算排除 undefined 传播的提前返回，确保非 undefined 边界先经过类型校验
  - Lexer: 未终止字符串字面量抛出 `S0101`（双引号）/ `S0105`（反引号）
  - Parser: `expect()` 不匹配时抛出 `S0202`；尾部 token 抛出 `S0201`；Lambda 参数非 `$name` 抛出 `S0208`；非变量 `:=` 抛出 `S0212`；意外 token 抛出 `S0211`；输入结束抛出 `S0207`
  - Tests: 新增 errors case000/001/002/003/004/007/008/015/016/017/018/019/020/021 + range-operator case012/017/018/022/023 共 10 个回归断言
- 修复效果：`errors` group 23→9 fail（-14），`range-operator` group 7→0 fail（全绿），`parent-operator` 20→13（-7 连带受益）
- 已知限制：errors 剩余 9 个失败涉及更深层的解析器/求值器语义（如 `unknown(function)` 关键字冲突、`3(?)` 部分应用非函数 T1008、构造后过滤 S0209/S0210），留待后续轮次

上一轮修复（JSONata 函数签名系统完整实现 + $join undefined 分隔符兼容）：
- 提交：整体 pass 1492→1505 (+13)，fail 175→162 (-13)，通过率 89.6%→90.2%
- 门禁：`moon check` 0e0w，`moon test` 213/213 passed（+7 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Value: 新增 `value/signature.mbt`，实现 JSONata `parseSignature` 完整语义——支持 `?` 可选、`+` 可变、`-` 上下文、`:` 返回类型、`a<...>`/`f<...>` 类型参数、`(...)` 选择类型
  - Value: 新增 `validate_function_args` 入口，简单签名（如 `sn`/`sss`）走宽松校验保持兼容，复杂签名走严格校验
  - Value: 新增 `JsonataFunc::validate_args` 返回可能被包装（标量→单元素数组）的参数列表，使 `a<s>` 等数组参数能接收标量实参
  - Value: 数组参数校验子类型时，对 `m`（undefined）直通，对数组实参逐元素检查（T0412），对标量实参按子类型校验后包装
  - Value: 实现回溯匹配算法，对齐 JSONata-js 正则 `^(p1)(p2)...(pN)$` 的贪婪与回溯语义，正确处理可变参数与后续必需参数的实参分配
  - Value: 可选/上下文/可变参数缺省时消费 `arg_idx` 位置（可能为 undefined）并递增，对齐 JSONata-js `signature.validate` 行为
  - Parser: 新增 `token_lexeme` 辅助函数，`parse_signature` 改为拼接原始词素（如 `a<s>s?:s`）而非 debug 字符串
  - Parser: 新增 `validate_signature_syntax` 在解析阶段校验签名语法，提前抛出 `S0401`（类型参数位置错误）/`S0402`（选择类型内嵌参数化类型），避免被后续 `expect('{')` 错误掩盖
  - Functions: `$join` 对 undefined 分隔符视为缺省（默认空字符串），与 JSONata-js 行为一致
  - Tests: 新增 function-signatures case011/012/026/027-029/030-033/034/035/040 共 7 个回归断言
- 已知限制：function-replace 5 个失败与调用路径相关（独立于本轮修改）

上一轮修复（undefined/null 传播 + HOF 兼容 + 函数验证完善）：
- 提交：整体 pass 1395→1492 (+97)，fail 272→175 (-97)，通过率 83.7%→89.6%
- 门禁：`moon check` 0e0w，`moon test` 206/206 passed，`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Functions: `$number()` 对 null/array/object/function 输入抛出 T0410；多余参数抛出 T0410
  - Functions: `$max/$min` 严格数字数组验证，混合类型抛出 T0412；多余参数抛出 T0410
  - Functions: `$length()` 改为非上下文感知，仅接受字符串；0 参数抛出 T0411；非字符串抛出 T0410
  - Functions: `$split()` 在 regex.mbt 注册版本添加类型验证（字符串/正则 pattern）和 limit 验证（D3020 负数/T0410 非法类型）
  - Functions: `$replace()` 对 undefined 首参返回 undefined
  - Evaluator: `should_partial_on_missing` 禁用隐式部分应用
  - Functions: `average/max/min/formatNumber` invoke 从 `fn` 改为 `=>` 消除 deprecated_syntax warning
- 已知限制：function-replace 8 个失败与调用路径相关（独立于本轮修改）
- 已知限制：审计脚本升级后口径扩大（eligible 1251→1667），新增 expected-error 和 code-mismatch 检测

上一轮修复（map 后位置谓词重置与重复父级跳过修正）：
- 提交：joins 27→28 pass（1→0 fail, -1），parent-operator 19→20 pass（1→0 fail, -1），整体 pass 1249→1251 (+2)，fail 2→0 (-2)，通过率 99.84%→100%
- 门禁：`moon check` 0e0w，`moon test` 204→206 passed（+2 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: frame 路径中的 `Map#$var` 改为按每个输入 frame 局部绑定位置变量，并让 map 后的位置谓词按每个输入项重置，修复 `$.$#$pos[$pos<3]` 与 `$.$[[0..2]]` 等价性
  - Evaluator: `parent_frames` 在连续父级导航时跳过重复的相同父级，修复多级 focus 后 `%.%` 停留在重复父级的问题
  - Tests: 新增 map 后位置谓词重置与多级 focus `%.%` 父级链回归断言
- 已知限制：当前 CLI 可比对官方用例已全通过；skip 仍为 harness/非字符串表达式/外部 bindings 等不可直接比较项

上一轮修复（字段数组位置谓词分组判定修正）：
- 提交：transform 56→57 pass（1→0 fail, -1），performance 0→1 pass（1→0 fail, -1），整体 pass 1247→1249 (+2)，fail 4→2 (-2)，通过率 99.68%→99.84%
- 门禁：`moon check` 0e0w，`moon test` 203→204 passed（+1 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: `eval_path_from` 的 Name→Filter 分组逻辑改为仅在过滤器链后继续接 Index/Slice 时保留分组；普通位置谓词（如 `state.tempReadings[[1..4]]`）直接在字段数组整体上求值，避免先拆成元素导致 range 位置谓词失效
  - Tests: 新增字段数组位置谓词在数组构造中展平的官方等价回归断言
- 已知限制：
  - joins (1): `$.$#$pos[$pos<3]` tuple stream 重置
  - parent-operator (1): `library.loans@$L.books@$B...customers@$C...$keys(%.%)` 三级 focus + %.% 祖先链重复导致解析偏差

上一轮修复（focus 步非 group 分支父级链修正）：
- 提交：parent-operator 18→19 pass（2→1 fail, -1），joins 25→27 pass（3→1 fail, -2），整体 pass 1244→1247 (+3)，fail 7→4 (-3)，通过率 99.6%→99.68%
- 门禁：`moon check` 0e0w，`moon test` 202→203 passed（+1 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: `eval_path_frames` focus 非 group 分支，创建 input_frame 时使用 `frames[0].value`（保持 @ 正确）和 `frame.ancestors`（step_frame 的正确祖先链），替代旧的 `frames`（祖先链陈旧导致 `%` 在多级 focus 路径中解析到错误层级）
  - Tests: 新增 dual-focus $keys(%) 父级键列表在 tuple stream + map 内解析回归断言
- 已知限制：
  - joins (1): `$.$#$pos[$pos<3]` tuple stream 重置
  - parent-operator (1): `library.loans@$L.books@$B...customers@$C...$keys(%.%)` 三级 focus + %.% 祖先链重复导致解析偏差（jsonata-js v2.2.1 同样返回空，属上游未实现行为）
  - performance (1): `$$.items[$i]` 父级引用配合位置绑定（tuple stream 架构问题）
  - transform (1): `state.tempReadings[[1..4]]` slice 展平（tuple stream）
  - 注：剩余 4 个失败用例在 JSONata-js v2.2.1 中同样不通过（返回空），属于上游未实现行为

上一轮修复（focus 步 tuple stream 路径继续语义对齐）：
- 门禁：`moon check` 0e0w，`moon test` 199→201 passed（+2 新增回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: `steps_has_arrayify` 递归检查 `Eval(expr)` 步内部的表达式（如 Sort 内嵌的 Path），新增 `ast_has_arrayify` 函数递归检测 Path/Sort/Block——修复 `[]` 出现在 Sort 输入路径中（如 `$#$pos[][$pos<3]^($)[-1]`）时 arrayify 未被应用的问题
  - Evaluator: `eval_step_frame_single` 中 `Eval(expr)` 步，当 expr 为 Path 或 Block([Path]) 时，通过 `eval_path_frames` 求值内部路径以保留祖先链——修复 `(Account.Order.Product)[%.OrderID='order104']` 中 parenthesized 表达式丢失祖先信息导致 `%` 父级引用返回 null 的问题
  - Tests: 新增 arrayify 递归检测 + parenthesized 路径祖先链保留 2 个回归断言
- 已知限制：
  - joins (3): `^($e.field)` sort + tuple binding + `.{ }` 路径（sort 后 focus 步递归重新求值丢失排序顺序）、`$.$#$pos[$pos<3]` tuple stream 重置
  - parent-operator (4): `$keys(%)` 父级键列表、`%.%` 多级父级链、`library.loans@$L.books@$B` 多级 focus + parent
  - performance (1): `$$.items[$i]` 父级引用配合位置绑定（tuple stream 架构问题）
  - transform (1): `state.tempReadings[[1..4]]` slice 展平（tuple stream）

上一轮修复（focus 绑定传播 + sort frames 提取）：
- 提交：整体 pass 1240→1240（无变化，但修复了 sort+focus 的中间态），`moon test` 198→199 passed（+1 新增 sort+focus 回归断言），通过率 99.2%
- 门禁：`moon check` 0e0w，`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: focus 步在 `has_group=false` 的递归路径中，将 focus 绑定传播到结果 frames（`bind_frame`），使后续步（sort、filter、map）能访问 bound 变量——修复 `Employee@$e^($e.Surname).$e.Surname` 返回 null 的问题
  - Evaluator: 从 `eval_sort_frames` 提取 `sort_frames_by_terms` 函数，支持对传入的 frames 按排序键排序（保留 frame bindings 和 ancestors），为后续 sort+tuple stream 链式求值做准备
  - Tests: 新增 sort 后 focus 绑定变量传播回归断言

上一轮修复（joins tuple stream group 聚合 reduce）：
- 提交：joins 18→21 pass（7→4 fail, -3），整体 pass 1237→1240 (+3)，fail 14→11 (-3)，通过率 99.0%→99.2%
- 门禁：`moon check` 0e0w，`moon test` 198/198 passed（+1 新增 joins 回归断言），`moon fmt` 与 `moon info` 已执行，`moon build cmd/main --target native` 通过
- 修复内容：
  - Evaluator: 新增 `access_group_aggregate_tuple_stream` 函数，处理 tuple stream 模式下的分组聚合——按 key 分组后，对每组的 frames 执行 reduce（合并绑定 + 追加 @ 值），再以 reduced 上下文求值 value-expression
  - Evaluator: `access_group_aggregate_frames` 检测 frames 是否携带 focus 绑定（tuple stream 模式），是则走新的 reduce 路径，否则走原 per-frame 求值路径
  - Evaluator: focus 步在 `has_group=true` 时，将 focus 绑定传播到 frames 但保留 `@` 为原始输入（对齐 JSONata-js `evaluateTupleStep` 语义——focus 不改变 `@`，只绑定变量）
  - Evaluator: 新增 `append_tuple_binding` 函数，实现 tuple 绑定追加（Sequence/Array/标量三种情况的合并）
  - Evaluator: reduce 阶段同时追加 `@`（frame.value），匹配 JSONata-js `reduceTupleStream` 对所有 tuple 属性（包括 `@`）的 append 语义
  - Tests: 新增 joins tuple stream group reduce 回归断言（Hugh Jones 3 Contacts 合并 + mobile 过滤）

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
