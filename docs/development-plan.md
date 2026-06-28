# Moonata 开发计划

> 8 阶段开发计划，含 17 个 Git 提交节点。
> 每阶段须通过验证后才能提交；提交信息遵循约定式提交规范。

## 1. 总览

| 阶段 | 主题 | 涉及包 | 提交节点数 | 预估人日 |
| --- | --- | --- | --- | --- |
| P1 | 基础类型层 | error / ast / value | 2 | 4 |
| P2 | 词法分析 | lexer | 1 | 3 |
| P3 | 语法分析 | parser | 2 | 6 |
| P4 | 求值器核心 | evaluator | 2 | 6 |
| P5 | 路径与表达式 | evaluator | 2 | 6 |
| P6 | 内建函数 | functions | 3 | 10 |
| P7 | 高级特性 | evaluator / functions | 3 | 8 |
| P8 | CLI 与集成 | moonata / cmd/main | 2 | 4 |
| 合计 | | | **17** | **47** |

## 2. Git 提交规范

### 2.1 提交信息格式

```
<type>(<scope>): <subject>

<可选正文：说明动机、验证结果、风险>
```

- **type**：`feat` / `fix` / `refactor` / `test` / `docs` / `chore` / `perf`
- **scope**：`ast` / `lexer` / `parser` / `evaluator` / `functions` / `value` / `error` / `cli` / `core`
- **subject**：祈使句，中文或英文均可，≤50 字符

### 2.2 提交前置条件（阶段门禁）

每次提交前必须满足：

1. `moon check` 通过（零错误，警告已处理）。
2. `moon test` 通过（本阶段相关测试全绿）。
3. `moon fmt` 已执行（代码已格式化）。
4. `moon info` 已执行，`.mbti` 变更符合预期。
5. 若涉及公开 API 变更，已更新对应测试。

### 2.3 提交节奏

- 每个提交节点对应一个阶段的可验证里程碑。
- 跨阶段的破坏性变更须在提交信息正文标注 `BREAKING:`。
- 禁止 `--no-verify` 跳过 pre-commit 钩子（`moon check`）。

## 3. 阶段明细

### P1 — 基础类型层（error / ast / value）

**目标**：建立错误层级、AST 定义、运行时值类型。

| 任务 | 包 | 验证 |
| --- | --- | --- |
| 定义 `JsonataError` suberror 层级 | error | `moon check` + 错误构造测试 |
| 实现 `Ast` enum 及 `Step`/`SortTerm` | ast | `derive(Debug)` + 相等测试 |
| 实现 `JsonataValue` 与序列操作 | value | 序列展平/单例提升测试 |
| 实现 `EvalContext` 与递归护栏 | value | 护栏触发测试 |

**提交节点：**
- **C1** `feat(error): 定义 JSONata 错误类型层级` — error 包完成
- **C2** `feat(ast,value): 定义 AST 节点与运行时值类型` — ast/value 包完成

### P2 — 词法分析（lexer）

**目标**：将源码切分为 token 流。

| 任务 | 验证 |
| --- | --- |
| 定义 `Token` enum（含位置信息） | `moon check` |
| 实现 `Lexer` 递归扫描（字符串、数字、运算符、标识符） | 全 token 类型快照测试 |
| 处理注释、空白、字符串转义 | 边界用例测试 |

**提交节点：**
- **C3** `feat(lexer): 实现词法分析器与 token 流生成` — lexer 包完成

### P3 — 语法分析（parser）

**目标**：token 流 → AST。

| 任务 | 验证 |
| --- | --- |
| 递归下降骨架、表达式优先级 | 算术/布尔表达式解析测试 |
| 路径、下标、切片、谓词过滤 | 路径解析快照测试 |
| 分组 `{}`、排序 `^`、Lambda、函数链 `~>` | 语法错误用例测试 |
| 序列构造 `[]`、块表达式 | 结构化 AST 断言 |

**提交节点：**
- **C4** `feat(parser): 实现表达式与路径解析` — 基础语法完成
- **C5** `feat(parser): 实现分组、排序、Lambda 与函数链` — 完整语法覆盖

### P4 — 求值器核心（evaluator）

**目标**：Ast → JsonataValue，含上下文与序列语义。

| 任务 | 验证 |
| --- | --- |
| 字面量、变量、绑定求值 | 基础求值测试 |
| `EvalContext` 绑定查找、`$`/`@`/`$$` 语义 | 上下文测试 |
| `Undefined` 传播规则 | 传播用例测试 |
| 递归/步数护栏触发 | 护栏错误测试 |

**提交节点：**
- **C6** `feat(evaluator): 实现字面量、变量与上下文求值` — 核心 eval
- **C7** `feat(evaluator): 实现 undefined 传播与递归护栏` — 语义完整

### P5 — 路径与表达式（evaluator）

**目标**：路径遍历、谓词、二元/一元运算、序列构造。

| 任务 | 验证 |
| --- | --- |
| 字段访问、递归降序 `**`、通配符 `.*` | 路径遍历测试 |
| 下标、切片、谓词过滤（布尔/位置） | 谓词用例测试 |
| 算术、比较、布尔、字符串拼接、`&` 合并 | 运算语义测试 |
| 序列构造与展平 | 序列测试 |

**提交节点：**
- **C8** `feat(evaluator): 实现路径遍历与谓词过滤` — 路径完成
- **C9** `feat(evaluator): 实现运算符与序列构造` — 表达式完成

### P6 — 内建函数（functions）

**目标**：60+ 内建函数分批实现。

| 任务 | 验证 |
| --- | --- |
| 函数注册表、签名系统、`$eval`/`$now` 等 | 注册表测试 |
| 字符串：`$concat`/`$substring`/`$trim`/`$split`/`$length` 等 | 字符串函数测试 |
| 数值：`$sum`/`$max`/`$min`/`$abs`/`$floor`/`$ceiling`/`$round` | 数值函数测试 |
| 聚合/数组：`$map`/`$filter`/`$reduce`/`$each`/`$sort`/`$count`/`$append`/`$flatten` | 高阶函数测试 |
| 对象：`$keys`/`$values`/`$merge`/`$spread`/`$sift`/`^` | 对象函数测试 |
| 类型转换：`$string`/`$number`/`$boolean`/`$type` | 转换测试 |
| 正则相关：`$match`/`$contains`/`$split`（正则模式） | 评估实现路径后补 |

**提交节点：**
- **C10** `feat(functions): 实现函数注册表与签名系统` — 注册框架
- **C11** `feat(functions): 实现字符串、数值与聚合函数` — 基础函数集
- **C12** `feat(functions): 实现对象、类型转换与正则相关函数` — 完整函数集

### P7 — 高级特性（evaluator / functions）

**目标**：分组、排序、Lambda、部分应用、函数链、自定义扩展。

| 任务 | 验证 |
| --- | --- |
| 分组表达式 `{ }` 求值、多级分组 | 分组用例测试 |
| 排序表达式 `^` 求值、多键排序 | 排序测试 |
| Lambda 求值、闭包捕获、部分应用 | Lambda 测试 |
| 函数链 `~>` 求值、自定义函数注册 | 链式与扩展测试 |

**提交节点：**
- **C13** `feat(evaluator): 实现分组与排序表达式` — 分组/排序
- **C14** `feat(evaluator): 实现 Lambda 与部分应用` — 函数式特性
- **C15** `feat(functions): 实现函数链与自定义函数扩展` — 扩展能力

### P8 — CLI 与集成（moonata / cmd/main）

**目标**：facade API、CLI、端到端集成测试。

| 任务 | 验证 |
| --- | --- |
| facade `evaluate`/`compile` API | facade 测试 |
| CLI：`moonata '<expr>' --data file.json` | CLI 冒烟测试 |
| JSONata 官方测试套件移植（选取核心用例） | 集成回归测试 |
| 文档：README、API 文档 | 文档检查 |

**提交节点：**
- **C16** `feat(core): 实现 facade API 与 CLI 入口` — facade + CLI
- **C17** `test(core): 移植 JSONata 测试套件并完成集成回归` — 集成完成

## 4. 里程碑验收标准

| 里程碑 | 验收 |
| --- | --- |
| C5 完成 | 全部合法 JSONata 表达式可解析为 AST，非法语法报 `SyntaxError` |
| C9 完成 | 纯表达式（无内建函数）可正确求值 |
| C12 完成 | 60+ 内建函数可用，核心用例通过 |
| C15 完成 | 分组、排序、Lambda、函数链全部可用 |
| C17 完成 | 官方测试套件核心用例通过，CLI 可用 |

## 5. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| MoonBit 无正则库 | `$match`/`$contains` 受限 | P6 评估第三方库或简化匹配；必要时标记为实验特性 |
| 序列语义复杂 | 求值器易出 bug | P1 在 value 包集中实现展平/提升，单测覆盖 |
| 递归过深 | 栈溢出/性能 | `EvalContext` 护栏（depth/steps） |
| 官方测试套件庞大 | P8 工作量膨胀 | 选取核心分类用例，非核心用例按优先级滚动补齐 |
