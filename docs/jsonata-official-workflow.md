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

当前固定快照（2026-07-04，descendent-operator 兼容性修复阶段，使用 `scripts/jsonata_official_audit.py` 审计）：

```text
eligible 1251 pass 1052 fail 199 skip 431
top_failures
joins 23
parent-operator 20
function-formatNumber 16
sorting 16
function-fromMillis 15
flattening 12
transforms 11
function-tomillis 10
function-sort 6
hof-map 6
skip_reasons
no_result 395
non-string-expr 23
timelimit 7
bindings 6
```

本轮修复（descendent-operator 兼容性）：
- 提交：descendent-operator 7→0，总体 pass 1044→1052（+8），fail 207→199（-8），通过率 83.5%→84.1%
- 门禁：`moon check` 0 error，`moon test` 174/174 passed，`moon info` OK
- 修复内容：
  - Parser: `"foo"` 在路径上下文中当作字段名（case003/005）
  - Parser: `.**.name` / `**.Name` 合并为 Name(Recursive)（case000/008/012）
  - Parser: `** .X [0]` 合并 index 到递归步（case009/013）
  - Evaluator: replace collect_recursive with depth-first descend_apply
  - Evaluator: Name/Index 递归步仅对 Object 应用，避免数组展开重复
  - Evaluator: access_index 对非 Array/Sequence 值返回原值（[0] no‑op）

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

本轮修复完成后，在 `docs/development-plan.md` 和 `.codebuddy/rules/moonata_项目实现指南.mdc` 中同步最新快照。

## 11. 提交节奏

每个阶段提交应是可验证里程碑，提交信息使用约定式格式：

```text
fix(functions): align tomillis parsing
fix(evaluator): preserve parent context in joins
test(core): add official flattening regressions
docs: update official jsonata workflow
```

提交前确认：

- 本地门禁全绿；
- 官方审计快照已更新；
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
