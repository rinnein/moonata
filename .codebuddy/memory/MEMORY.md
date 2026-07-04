# Moonata 项目长期记忆

## 项目定位
- 模块名 `rinnein/moonata`，MoonBit 项目，目标：将 JSONata 移植至 MoonBit。
- preferred-target: `wasm-gc`。

## 架构核心（详见 docs/architecture.md）
- 8 库包：error / ast / value / lexer / parser / evaluator / functions / moonata(facade) + cmd/main。
- 依赖无环，自底向上：error → {ast, value, lexer} → parser → evaluator → functions → moonata → cmd/main。
- ast 与 value 互不依赖；parser 不依赖 value/evaluator。

## 关键类型
- `Ast`：单一 enum（20+ 节点），子结构 Step/SortTerm，derive(Debug)。
- `JsonataValue`：四态 enum（Json/Sequence/Func/Undefined），序列元素恒为 Json。
- `JsonataError`：单一 suberror，5 变体（Syntax/Runtime/Type/Signature/Guardrail）。
- `EvalContext`：持有 root、bindings、depth/steps 护栏。

## 开发规范
- 提交信息：`<type>(<scope>): <subject>`，17 个节点 C1–C17（见 docs/development-plan.md）。
- 阶段门禁：moon check + moon test + moon fmt + moon info 全绿方可提交。
- 禁止 --no-verify 跳过 pre-commit 钩子（执行 moon check）。
- block 风格 `///|`；小而内聚的文件；不为调试派生 Show，用 debug_inspect+Debug。

## 已知风险
- ~~R1：MoonBit 标准库无正则，影响 $match/$contains，P6 评估第三方或简化实现。~~ **已解决**：引入 `moonbitlang/regexp@0.3.5`（API: `compile`/`Regexp::execute`/`MatchResult`），P9.4 实现。
- ~~已知语义缺口：`@`/`$$` 上下文简化为根、谓词过滤未绑定当前项、`&` 未做对象合并、部分应用未实现。~~ **已解决**：P9 全部修复。

## 项目状态（P9 完成后）
- 174 个测试全绿，moon check/test/fmt/info 通过。
- CLI native 目标端到端可用：`moon run cmd/main --target native -- '<expr>' --data '<json>'`。
- 内建函数 60+，含正则函数（$match/$contains_regex/$split_regex/$replace_regex）。
- 8 阶段 + P9 语义修复全部完成，17+5=22 个提交节点（C1-C22）。
- 通用 date picture parser 已实现，支持 word number、roman numeral、ordinal 等格式。
- 官方审计基线（2026-07-04）：eligible 1251 pass 1080 fail 171 skip 431（审计脚本 `scripts/jsonata_official_audit.py`，通过率 86.3%）

## 项目文件布局
- 设计文档在 `docs/`（architecture / development-plan / design-decisions）。
- 智能体规则在 `.codebuddy/rules/`（已纳入版本控制，.gitignore 放行 rules/）。
- pre-commit 钩子在 `.githooks/pre-commit`。
