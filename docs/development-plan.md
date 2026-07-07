# Moonata 开发计划

> 8 阶段开发计划，含 17 个 Git 提交节点（P1–P8 已完成）。
> P9 为语义修复与函数补全阶段，已完成。
> P10 为本地验收收尾阶段，已补齐门禁、兼容性基础与文档状态。
> P11 为 JSONata 官方测试集全量兼容推进阶段，当前暂停在已验证快照。
> 每阶段须通过验证后才能提交；提交信息遵循约定式提交规范。

## 1. 总览

| 阶段 | 主题 | 涉及包 | 提交节点数 | 预估人日 | 状态 |
| --- | --- | --- | --- | --- | --- |
| P1 | 基础类型层 | error / ast / value | 2 | 4 | ✅ 完成 |
| P2 | 词法分析 | lexer | 1 | 3 | ✅ 完成 |
| P3 | 语法分析 | parser | 2 | 6 | ✅ 完成 |
| P4 | 求值器核心 | evaluator | 2 | 6 | ✅ 完成 |
| P5 | 路径与表达式 | evaluator | 2 | 6 | ✅ 完成 |
| P6 | 内建函数 | functions | 3 | 10 | ✅ 完成（已注册 60+ 函数） |
| P7 | 高级特性 | evaluator / functions | 3 | 8 | ✅ 完成（部分应用已实现） |
| P8 | CLI 与集成 | moonata / cmd/main | 2 | 4 | ✅ 完成（CLI native 参数模式可用） |
| P9 | 语义修复与函数补全 | evaluator / functions / value | 5 | 12 | ✅ 完成 |
| P10 | 验收收尾与兼容性补齐 | value / evaluator / functions / docs | 4 | 7 | ✅ 完成 |
| P11 | 官方测试集全量兼容推进 | parser / evaluator / functions / docs | 滚动 | 待评估 | 🚧 推进中（1170/1251 可比对用例通过） |
| 合计 | | | **26** | **66** | |

> 当前固定快照（2026-07-07，简单数组选择器逐项索引修复阶段）：`moon test` 为 182/182 通过；`moon check`、`moon info` 通过；`moon fmt` 已执行。JSONata 官方可比对审计为 `eligible 1251 / pass 1170 / fail 81 / skip 431`（审计脚本：`scripts/jsonata_official_audit.py`）。

### 1.1 当前暂停边界

P11 已完成日期时间 picture 修复、Lambda 签名语法与范围表达式修复、Lambda 闭包与反引号字段名修复（`closures` 可比对用例 2/2）、字符串字面量谓词过滤修复（`conditionals` 可比对用例 7/7）、简单数组选择器逐项索引修复（`simple-array-selectors` 可比对用例 23/23，`flattening` 失败降至 4）、多索引数组选择器修复（`multiple-array-selectors` 可比对用例 3/3，`joins` 失败降至 10）、`$keys` 对象序列修复（`function-keys` 可比对用例 3/3）、`$spread` 非对象与对象序列修复（`function-spread` 可比对用例 3/3）、`$sift` predicate 三参和空结果省略修复（`function-sift` 可比对用例 5/5）、递归通配容器保留与去重修复（`descendent-operator` 可比对用例 15/15）、`$reverse` 数组返回与数组构造展开修复（`function-reverse` 可比对用例 3/3）、整数 picture 修复、`$string` 序列化修复（`function-string` 可比对用例 26/26）、`&` 字符串拼接 undefined 与序列字符串化修复（`string-concat` 可比对用例 12/12）、无空格二元减法修复（`lambdas` 可比对用例 11/12）、比较运算修复（`comparison-operators` 可比对用例 41/41）、`$average` 与数字拼接修复（`function-average` 可比对用例 5/5）、`$zip` 可变参数修复（`function-zip` 可比对用例 6/6）、`in` 运算符修复（`inclusion-operator` 可比对用例 9/9）、`$ceil` 函数别名修复（`function-ceil` 可比对用例 3/3）、`$formatBase` 兼容修复（`function-formatBase` 可比对用例 6/6）、`$formatNumber` zero-digit 与负数子图修复（`function-formatNumber` 可比对用例 26/26）、`$fromMillis` picture 与空括号修复（`function-fromMillis` 可比对用例 88/88）、`$join` 默认分隔符与链式调用修复（`function-join` 可比对用例 7/7）、函数调用默认上下文实参修复（`context` 可比对用例 4/4，`function-signatures` 可比对用例 30/30）、`$split` 空分隔符与 limit 修复（`function-split` 可比对用例 11/11）、`$shuffle` 数组函数修复（`function-shuffle` 可比对用例 3/3）、`$single` predicate 修复（`hof-single` 可比对用例 6/6）、通用 date picture parser 实现（`function-tomillis` 从 34 → 17 失败，支持 word number/roman numeral/ordinal 等格式），后续继续优先处理官方失败数最高的 group：

| 排名 | 官方 group | 失败数 |
| --- | --- | --- |
| 1 | `parent-operator` | 20 |
| 2 | `function-tomillis` | 10 |
| 3 | `joins` | 10 |
| 4 | `transforms` | 10 |
| 5 | `variables` | 5 |
| 6 | `flattening` | 4 |
| 7 | `function-applications` | 2 |
| 8 | `object-constructor` | 2 |
| 9 | `transform` | 2 |
| 10 | `boolean-expresssions` | 1 |

跳过项仅表示当前 CLI 审计 harness 无法直接比较，不表示通过或失败：`no_result 395`、`non-string-expr 23`、`timelimit 7`、`bindings 6`。

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
| 函数注册表、基础元数检查、`$eval`/`$now` 等 | 注册表测试 |
| 字符串：`$concat`/`$substring`/`$trim`/`$split`/`$length` 等 | 字符串函数测试 |
| 数值：`$sum`/`$max`/`$min`/`$abs`/`$floor`/`$ceiling`/`$round` | 数值函数测试 |
| 聚合/数组：`$map`/`$filter`/`$reduce`/`$each`/`$sort`/`$count`/`$append`/`$flatten` | 高阶函数测试 |
| 对象：`$keys`/`$values`/`$merge`/`$spread`/`$sift`/`^` | 对象函数测试 |
| 类型转换：`$string`/`$number`/`$boolean`/`$type` | 转换测试 |
| 正则相关：`$match`/`$contains`/`$split`（正则模式） | 评估实现路径后补 |

**提交节点：**
- **C10** `feat(functions): 实现函数注册表与元数检查` — 注册框架
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

### P9 — 语义修复与函数补全（evaluator / functions / value）

**目标**：修复影响 JSONata 兼容性的语义缺口，补全内建函数至 60+，引入正则支持。

> 任务按优先级排序。正则依赖 `moonbitlang/regexp@0.3.5`（已加入 `moon.mod`）。

**优先级说明**：
- 🔴 高：影响核心 JSONata 兼容性，现有表达式语义错误
- 🟡 中：函数完整性，影响可用性
- 🟢 低：工程化与集成

#### P9.1 🔴 上下文与谓词语义修复（value / evaluator）

| 任务 | 包 | 验证 |
| --- | --- | --- |
| `EvalContext` 增加 `current`/`parent` 字段，支持 `@` 当前项、`$$` 父级 | value | `@`/`$$` 上下文测试 |
| `eval_var` 正确解析 `@`（当前项）与 `$$`（父级），不再简化为根 | evaluator | 上下文断言测试 |
| `access_filter` 迭代时将 item 绑定为当前上下文，使谓词可访问当前项字段 | evaluator | 谓词过滤用例（`$x.age > 25`） |
| 路径求值链中维护 `current`/`parent` 的压栈与恢复 | evaluator | 嵌套路径上下文测试 |

**提交节点：**
- **C18** `fix(evaluator,value): 修复 @/$$ 上下文与谓词过滤语义` — 核心语义修复

#### P9.2 🔴 `&` 合并运算符与表达式补全（evaluator）

| 任务 | 包 | 验证 |
| --- | --- | --- |
| `&` 对对象执行合并（深度合并），对字符串执行拼接 | evaluator | 对象合并测试 + 字符串拼接测试 |
| 部分应用：`eval_apply` 支持参数不足时返回柯里化函数 | evaluator | 部分应用测试 |

**提交节点：**
- **C19** `feat(evaluator): 实现 & 对象合并与部分应用` — 表达式语义补全

#### P9.3 🟡 内建函数补全至 60+（functions）

| 任务 | 包 | 验证 |
| --- | --- | --- |
| 字符串：`$replace`/`$substringBefore`/`$substringAfter`/`$pad`/`$formatNumber` | functions | 字符串函数测试 |
| 数值：`$sqrt`/`$pi`/`$e`/`$formatBase` | functions | 数值函数测试 |
| 数组：`$distinct`/`$single`/`$partition`/`$zip` | functions | 数组函数测试 |
| 对象/其他：`$assert`/`$shallow`/`$deep` | functions | 对象函数测试 |
| 修复占位函数：`$base64encode`/`$base64decode`（真编码） | functions | 占位函数回归测试 |

**提交节点：**
- **C20** `feat(functions): 补全字符串、数值与数组函数至 60+` — 函数集完整

#### P9.4 🟡 正则函数实现（functions）

> 依赖 `moonbitlang/regexp@0.3.5`：`compile` + `Regexp::execute` + `MatchResult`。

| 任务 | 包 | 验证 |
| --- | --- | --- |
| `$match(str, pattern)`：返回首个匹配及捕获组 | functions | 正则匹配测试 |
| `$contains_regex(str, pattern)`：正则模式包含判断 | functions | 正则包含测试 |
| `$split_regex(str, separator)`：支持正则分隔符 | functions | 正则分割测试 |
| `$replace_regex(str, pattern, replacement)`：正则替换 | functions | 正则替换测试 |
| `$matches`（可选）：返回所有匹配 | functions | 多匹配测试 |

**提交节点：**
- **C21** `feat(functions): 基于 moonbitlang/regexp 实现正则函数` — 正则支持完成

#### P9.5 🟢 集成与文档（moonata / cmd/main / docs）

| 任务 | 包 | 验证 |
| --- | --- | --- |
| CLI 切换 native 目标，支持 `moonata '<expr>' --data file.json` 命令行参数 | cmd/main | CLI 冒烟测试 |
| JSONata 官方测试套件核心用例移植（选取 path/predicate/function 分类） | moonata_test | 集成回归测试 |
| 日期函数完善：`$fromMillis`/`$toMillis`（native 目标，`$formatDateTime` 转 P10） | functions | 日期函数测试 |
| 文档同步：修正核心设计文档中的过时状态 | docs | 文档检查 |
| README 与 API 文档完善 | docs | 文档检查 |

**提交节点：**
- **C22** `test(core): 移植官方测试套件并完善 CLI 与文档` — 集成完成

### P10 — 验收收尾与兼容性补齐（value / evaluator / functions / docs）

**目标**：解决 P9 审查中发现的严格验收缺口，使计划状态、代码实现与阶段门禁一致。

> P10 不扩大 JSONata 范围，只补齐已写入计划但当前实现未满足的项目，并清理 MoonBit 工具链 warning。当前已完成。

#### P10.1 🔴 门禁与文档状态修正

| 任务 | 包 | 验证 |
| --- | --- | --- |
| 清理 `moon check` / `moon info` warning：废弃 API、未使用变量、缺失模式参数、未标注 raise 闭包等 | evaluator / functions / value | `moon check` / `moon info` 0 warning |
| 移除或修正 `docs/architecture.md`、`docs/design-decisions.md` 中 P9 已完成但状态未同步的残留 | docs | 文档审查 |
| 将正则函数命名、日期函数范围、随机函数状态同步到所有 docs | docs | `rg` 无过时状态 |

**提交节点：**
- **C23** `chore(core): 清理工具链警告并同步文档状态` — 门禁收尾

#### P10.2 🔴 函数签名系统补齐

| 任务 | 包 | 验证 |
| --- | --- | --- |
| `JsonataFunc` 增加可选签名描述，保留现有 `arity` 兼容字段 | value | `.mbti` 变更符合预期 |
| `register` 支持签名元数据，内建函数按需声明参数/返回类型 | functions | 注册表测试 |
| 在函数调用入口执行类型检查，错误统一抛 `SignatureError` | evaluator / functions | 签名错误用例 |

**提交节点：**
- **C24** `feat(functions,value): 补齐函数签名系统` — 签名验收

#### P10.3 🟡 函数兼容性补齐

| 任务 | 包 | 验证 |
| --- | --- | --- |
| `$random` 从固定 `0.5` 改为真实随机值，范围为 `[0, 1)` | functions | 随机范围测试 |
| 实现 `$formatDateTime`，至少覆盖已文档化的 native 基础格式能力 | functions | 日期函数测试 |
| 评估正则标准函数名兼容：在保持 `$contains_regex` 等现有函数的同时，为 `$contains`/`$split`/`$replace` 提供正则模式路径或明确文档化差异 | functions / docs | 正则回归测试 |

**提交节点：**
- **C25** `feat(functions): 补齐随机日期与正则兼容接口` — 函数兼容性

#### P10.4 🟢 最终验收

| 任务 | 包 | 验证 |
| --- | --- | --- |
| 增补 P10 对应黑盒测试与核心集成测试 | functions / moonata | `moon test` |
| 执行完整门禁：`moon check`、`moon test`、`moon fmt`、`moon info` | 全部 | 0 错误、warning 已处理 |
| 更新本计划的总览、里程碑与风险状态为最终验收完成 | docs | 文档检查 |

**提交节点：**
- **C26** `test(core): 完成最终验收回归` — P10 完成

## 4. 里程碑验收标准

| 里程碑 | 验收 |
| --- | --- |
| C5 完成 | 全部合法 JSONata 表达式可解析为 AST，非法语法报 `SyntaxError` |
| C9 完成 | 纯表达式（无内建函数）可正确求值 |
| C12 完成 | 60+ 内建函数可用，核心用例通过 |
| C15 完成 | 分组、排序、Lambda、函数链全部可用 |
| C17 完成 | 官方测试套件核心用例通过，CLI 可用 |
| **C18 完成** | `@`/`$$` 上下文与谓词过滤语义正确，现有谓词用例通过 |
| **C19 完成** | `&` 对象合并与部分应用可用 |
| **C21 完成** | 正则函数（`$match`/`$contains_regex`/`$split_regex`/`$replace_regex`）可用 |
| **C22 完成** | 官方测试套件核心用例通过，CLI 支持命令行参数 |
| **C23 完成** | `moon check` / `moon info` warning 已清理，docs 状态无残留 |
| **C24 完成** | 函数签名系统可用，签名错误用例通过 |
| **C25 完成** | `$random`、`$formatDateTime` 与正则兼容接口达到计划要求 |
| **C26 完成** | 完整门禁通过，P1–P10 进入最终验收完成态 |

## 5. 风险与缓解

| 风险 | 影响 | 缓解 | 状态 |
| --- | --- | --- | --- |
| MoonBit 无正则库 | `$match`/`$contains` 受限 | ~~P6 评估第三方库~~ **已引入 `moonbitlang/regexp@0.3.5`**，P9.4 实现 | ✅ 已解决 |
| 序列语义复杂 | 求值器易出 bug | P1 在 value 包集中实现展平/提升，单测覆盖 | ✅ 已实现 |
| 递归过深 | 栈溢出/性能 | `EvalContext` 护栏（depth/steps） | ✅ 已实现 |
| 官方测试套件庞大 | P8/P9.5 工作量膨胀 | 已移植核心分类用例，非核心用例按优先级滚动补齐 | ✅ 核心完成 |
| 官方全量兼容仍有失败 | 与 jsonata-js 行为存在差距 | P11 按审计快照优先处理失败最多 group，每个阶段提交前固定新快照 | ⏸ 推进中 |
| `@`/`$$` 上下文缺失 | 谓词过滤语义错误 | P9.1 已在 `EvalContext` 增加 `current`/`parent` 字段 | ✅ 已实现 |
| 工具链 warning 未清理 | 不满足阶段门禁“警告已处理” | P10.1 已清理 deprecated / unused / pattern warning | ✅ 已解决 |
| 函数签名系统缺失 | 类型错误无法统一映射为 `SignatureError` | P10.2 已增加签名元数据与调用入口检查 | ✅ 已实现 |
| `$random` 与日期格式函数不完整 | 与 P9 计划不一致 | P10.3 已补齐随机范围与 `$formatDateTime` | ✅ 已实现 |

## 6. 官方测试集审计流程

官方测试集实现闭环以 `docs/jsonata-official-workflow.md` 为准；`.codebuddy/rules/moonata_项目实现指南.mdc` 第 8 节保留简版审计口径。更新完成度时必须复跑 native CLI 审计，并同步本文件的固定快照、失败前 10 group 与 skip 原因。
