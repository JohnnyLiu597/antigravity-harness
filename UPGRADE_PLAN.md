> Historical proposal, not a claim of current implementation or measured performance. See README.md and docs/production-readiness.md for current scope.

# Antigravity Harness 架构升级与工程实现方案
> 从 Codex-Harness 经验到 Antigravity 原生工业级治理框架的演进规范
> 版本：v1.0.0-draft | 日期：2026-09-03 | 目标仓库：`JohnnyLiu597/antigravity-harness`

> **Historical notice:** This document records the original v1 design and may
> contain capability or model assumptions that were not proven by live runtime
> evidence. It is not the current execution contract. Use `V2_UPGRADE_PLAN.md`,
> `src/harness.capabilities.json`, and the v2 verification gate for current truth.

---

## 1. 升级背景与核心痛点分析

### 1.1 现状与演进路径
目前的 Antigravity 本地配置沿用了最初从 **Claude Code 2.1.88** 移植到 Codex 时的早期混合方案（`AGENTS.md v2.0`）。
在此期间，作者在 [`codex-harness`](https://github.com/JohnnyLiu597/codex-harness) 上进行了数十轮高强度工程迭代，成功沉淀出了包括**双层隔离架构、幂等同步流水线、验证封套（Verification Envelope）、上下文预算审计、组件注册表（Component Registry）与持续学习摄入**在内的完整方法论。

然而，现存的 Antigravity 配置存在明显的**水土不服与代差摩擦**：
1. **未分离维护源码与运行环境**：规则与技能直接散落在 `$env:USERPROFILE\.gemini`，混杂了本地凭证、对话历史、会话缓存与 SQLite 数据库，无法安全纳管至 Git。
2. **沉重的全局 Token 基础税**：无差别注入 800+ 行全局规则，每次简单交互（即便是一句话改动）都需要承担 5,000~8,000 Tokens 的上下文消耗。
3. **与 Antigravity 原生机能冲突**：
   - 使用粗糙的文本停顿词 `PAUSE_FOR_HUMAN`，放弃了 Antigravity 原生极其优雅的 `ask_question` 交互模态与 UI 审批流。
   - 强行在工作区生成 `artifacts/plan_*.md`，与 Antigravity 原生 `brain/<conversation-id>/` 的 Planning Mode（`implementation_plan.md` + `walkthrough.md`）割裂。
4. **模型路由能力严重滞后**：规则仍停留在早期的 `gemini-3-flash`，未适配最新的 **Gemini 3.8 Flash / Pro** 系列。
5. **Unix/Bash 痕迹残留**：依然存在 Linux 路径与 Bash 假定，未对 Windows PowerShell 作第一公民级优化。

### 1.2 升级目标
以 `codex-harness` 为蓝本，构建一套专属于 Google Antigravity 的、版本化的、完全解耦的开源治理框架——**`antigravity-harness`**。

---

## 2. 总体架构：双层模型与三大刚性边界

严格继承 `codex-harness` 经过实战检验的双层设计原则：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          ANTIGRAVITY HARNESS                            │
├─────────────────────────────────────────────────────────────────────────┤
│ 1. 源码仓库层 (Repository Source Layer)                                 │
│    <workspace>\antigravity-harness                 │
│    ├── src/             可发布、可审查的运行时资产镜像                  │
│    ├── deploy/          PowerShell 同步、打包与防泄漏验证工具链         │
│    ├── docs/            架构、命令、发布与测试规范                      │
│    └── artifacts/       [GitIgnored] 本地临时验证结果                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                  ▲ 同步 (sync-to / sync-from)           │
│                                  ▼ 过滤 (严格边界排除)                  │
├─────────────────────────────────────────────────────────────────────────┤
│ 2. 本地运行时层 (Local Runtime Layer)                                   │
│    <user-home>\.gemini                                          │
│    ├── AGENTS.md / GEMINI.md (轻量化全局入口)                           │
│    ├── skills/ (全局激活技能)                                           │
│    └── config/plugins/ (原生插件与 Sidecars)                            │
├─────────────────────────────────────────────────────────────────────────┤
│ 3. 私有运行时与状态隔离区 (Private Runtime State - 绝对禁止入库)        │
│    ├── antigravity/brain/ (对话级产物、工作区推理脑图)                   │
│    ├── antigravity/conversations/ (JSONL 会话日志)                      │
│    ├── *.pb, *.pbtxt, *.db (SQLite, Proto 状态文件)                     │
│    └── config/config.json (包含用户个人 token 与私有授权项)             │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 四大核心升级设计方案

### 方案一：自适应分级加载体系 (Adaptive Tiered Gating)
彻底打破“全量规则全局死磕”的弊端，引入动态两级加载：

* **Tier 0：静默轻量基线（Global Baseline，< 80 行）**
  * 默认注入 `~/.gemini/AGENTS.md`。
  * 仅包含最底层的防御规则：PowerShell 命令安全、3 次相同工具调用熔断（Anti-Looping）、核心通信风格、Windows 路径链接规范。
  * **Token 消耗直降 90%**，常规编程快速响应。
* **Tier 1：全功能长程治理装甲（Full Governance Armor）**
  * 激活条件：
    1. 工作区根目录下检测到 `mission.md` 或 `CONTEXT.md`；
    2. 用户触发高级 Slash 命令（如 `/goal`、`/boost`、`/teamwork-preview`）；
    3. 任务分类判定为 `coordinator` 或大型多步重构。
  * 激活内容：动态载入 6 大生命周期钩子（INIT、PRE_TOOL、POST_TOOL、CHECKPOINT、SHUTDOWN）、IAS 指令对齐自评分、强制锚点重读、标准 Trajectory 抓取。

### 方案二：深度拥抱 Antigravity 原生交互表面
将 Claude/Codex 遗留机制全面重构成 Antigravity 原生实现：

| 机制 | 遗留机制 (Claude Code 风格) | Antigravity-Harness 原生适配设计 |
| :--- | :--- | :--- |
| **人机交互门禁 (HITL)** | 文本输出 `PAUSE_FOR_HUMAN` 停顿词 | 调用原生的 `ask_question` 工具，弹出结构化选择框、单选/多选/手填项，用户体验完全原生化。 |
| **规划产物管理** | 强行在根目录写 `artifacts/plan_*.md` | 深度整合 Antigravity **Planning Mode**，收敛至 `brain/<conv-id>/implementation_plan.md`，并在完成时统一更新 `walkthrough.md`。 |
| **多模态与渲染** | 仅依赖控制台 Markdown 文本 | 结合 Antigravity 内置 `generative_ui` 与 Mermaid 引擎，自动可视化展示任务分解图（DAG）与状态仪表盘。 |
| **任务长程推进** | 模拟循环轮询 | 结合原生 `manage_task`、`schedule`（定时/Cron/条件触发）与 Reactive Wakeup 消息总线，杜绝低效 Polling。 |

### 方案三：适配 Gemini 3.8+ 现代智能体路由矩阵 (QueryConfig 2.0)
更新 [GEMINI.md](src/GEMINI.md) 中的模型路由引擎：
* **Fast Tier**：**Gemini 3.8 Flash**（默认用于工具执行、环境探索、只读检索、日志记录与上下文压缩）。
* **Reasoning Tier**：**Gemini 3.8 Flash (High Thinking) / Gemini 3.1 Pro**（用于架构拆解、Coordinator 聚合、复杂编译报错修复、IAS ≤ 3 漂移回溯）。
* **动态降级/恢复策略**：根据 IAS 评分和连续报错次数自动提升推理预算（Thinking Budget）。

### 方案四：Windows-First 与 PowerShell 工业级流水线
完全吸收 `codex-harness` 中极其成熟的 PowerShell 脚本体系，定制 Antigravity 版本：
* `deploy/sync-to-runtime.ps1`：将 `src/` 下维护的内容精确部署到 `$env:USERPROFILE\.gemini`。
* `deploy/sync-from-runtime.ps1`：从运行环境安全抓回最新经过实战修改的规则/技能，自动剥离任何 private 数据。
* `deploy/verify-package.ps1`：针对敏感字段、私有 Token、SQLite 状态、大临时文件的静态扫描门禁。
* `src/scripts/init-project-harness.ps1`：为目标工程一键初始化 Antigravity Harness 脚手架（生成 `mission.md`、`.agent/rules.md`、`CONTEXT.md`）。

---

## 4. 目录树规划 (Target Repository Structure)

```text
antigravity-harness/
├── .gitignore
├── LICENSE
├── README.md
├── UPGRADE_PLAN.md
├── mission.md
├── CONTEXT.md
├── MEMORY.md
├── docs/
│   ├── architecture.md          # 架构全景与双层设计理念
│   ├── commands.md              # 常用管理与同步命令
│   ├── antigravity-surfaces.md  # Antigravity 原生机能对接指南
│   ├── project.md               # 目标工作区接入规范
│   ├── release.md               # 发布与版本流转指南
│   └── testing.md               # 验证与测试规范
├── deploy/
│   ├── sync-to-runtime.ps1      # 源码 -> ~/.gemini 部署
│   ├── sync-from-runtime.ps1    # ~/.gemini -> 源码 提取
│   ├── verify-package.ps1       # 敏感信息与边界防泄漏检查
│   └── test-sync-boundaries.ps1 # 同步路径与边界单元测试
└── src/
    ├── AGENTS.md                # 部署到 ~/.gemini/AGENTS.md (轻量基线规则)
    ├── GEMINI.md                # 部署到 ~/.gemini/GEMINI.md (运行时配置与路由)
    ├── harness.capabilities.json# Harness 声明能力注册表
    ├── harness.components.json  # 组件依赖与版本清单
    ├── agents/                  # Antigravity 原生子智能体规范定义
    │   ├── architect.md
    │   ├── reviewer.md
    │   ├── tester.md
    │   ├── harness-auditor.md
    │   └── explorer.md
    ├── skills/                  # 精炼提取的核心治理与工程技能
    │   ├── harness-orchestrator/
    │   ├── context-guard/
    │   ├── tool-reliability/
    │   ├── trajectory-capture/
    │   ├── memory-extract/
    │   └── eval-harness/
    ├── scripts/                 # 跨项目辅助 PowerShell 脚本
    │   ├── init-project-harness.ps1
    │   ├── audit-context-budget.ps1
    │   ├── invoke-verification-gate.ps1
    │   └── new-learning-intake.ps1
    └── templates/               # 工程模板
        ├── mission.template.md
        ├── CONTEXT.template.md
        └── agent-rules.template.md
```

---

## 5. 实施路线图 (Phase Execution Plan)

1. **Phase 1: 脚手架建立与部署管道移植 (Day 1)**
   - 建立 `antigravity-harness` 基础结构。
   - 基于 `codex-harness` 的脚本移植并改造 Windows PowerShell 部署管道（修改路径为 `~/.gemini`，配置 Antigravity 专有排除规则）。
2. **Phase 2: 核心规则精简与分级体系重构 (Day 2)**
   - 编写轻量化 `src/AGENTS.md`（基线防死锁 + 通信风格）。
   - 编写现代 `src/GEMINI.md`（适配 Gemini 3.8、原生 `ask_question` 门禁与 Planning Mode 映射）。
3. **Phase 3: 子智能体与核心技能库迁移 (Day 3)**
   - 提取并重构 6 大核心 Harness 治理技能（剔除 ECC 中冗余低频技能）。
   - 编写 Antigravity 原生子智能体模板（支持 `invoke_subagent` 标准化传参）。
4. **Phase 4: 本地同步验证与实战回归测试 (Day 4)**
   - 运行 `deploy/verify-package.ps1` 验证防泄漏。
   - 部署到本机 `~/.gemini` 进行实机长任务压力测试与断点恢复测试。
5. **Phase 5: 文档健全与开源发布准备 (Day 5)**
   - 完善全套 `docs/` 文档。
   - 初始化 Git 仓库并推送到 GitHub `JohnnyLiu597/antigravity-harness`。
