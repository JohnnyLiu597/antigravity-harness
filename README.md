# Antigravity Harness

**让 Antigravity 的执行受约束，让完成结论有证据，并与 Codex 安全接力。**

A Windows-first, evidence-driven reliability harness for Google Antigravity Desktop,
with strict execution contracts and asymmetric Codex collaboration.

这是独立维护的工程项目，不是 Google 官方产品，也不是 Antigravity 本体的替代实现。
它来自维护者的实际使用：当智能体偏离范围、把工具执行当成任务完成、复用过时证据，
或在长任务中丢失约束时，仅增加提示词往往不够，需要可检查的任务契约与证据链。

> 这里的“强约束”不等于 `strict` 隔离模式已实现。本项目的 `strict` 模式仍不可用；
> 同用户任意执行和未覆盖工具不受完整 OS 隔离。源代码完成门控最多产生 `checking`，
> 不能凭模型角色、文件哈希或两个智能体一致意见自授 `verified`。

## 为什么需要它

下面区分“维护者关注的工作流风险”和“特定本机环境的实测记录”，不提供未经测量的
平台漂移率，也不声称所有 Antigravity 版本都存在相同问题。

| 风险或观察 | 我们如何约束 | 仍然不能保证什么 |
|---|---|---|
| 任务越做越大，偏离原目标或架构 | Contract 固定目标、非目标、允许路径、改动预算和必需检查 | 只有策略被读取、脚本被调用或已观察 hook 覆盖时才起作用 |
| Created/Ran、一次 Post 或模型自述被当成任务完成 | 分开 Tool Operation、Attempt、Report、Claim、Envelope、Decision | 工具成功不代表业务目标通过 |
| 修改了源码、测试或证据后仍沿用旧结论 | 重算当前内容哈希，绑定来源和明确证据引用，拒绝过时输入 | 哈希证明内容一致性，不证明操作者身份 |
| 失败后换 task/root 或“选最新文件”掩盖历史 | 稳定逻辑任务 ID、显式引用、保留失败和重试 | 不自动修复缺失的历史原件 |
| 测试环境中 force_ask 未弹出确认，写入仍发生 | 受保护场景使用明确 Binding 和 deny，而不是依赖内联询问 | 这是特定环境观察，不是对所有版本的判断 |
| 个别 Pre 没有对应 Post | 保留 unresolved，不补造回调或猜测成功 | 缺失事件的宿主根因尚未确认 |

详见 [问题、证据与设计取舍](docs/why-this-harness.md)。

## 约束架构

任务约定 → Contract → Attempt / Binding → Tool Operations → 实际检查 → 固定证据 → Report / Claim / Envelope → Completion Gate。

- **范围约束**：执行前确定边界；扩范围、迁移、发布等操作仍需用户授权。
- **执行约束**：绑定真实会话、角色和正在运行的 Attempt；支持到期、撤销与收窄。
- **结果约束**：实际退出码、收集到的测试与当前输入比“输出看起来成功”更重要。
- **恢复约束**：保留失败、重试和过时证据，不通过重建身份美化结果。
- **权限约束**：maker、runner、reviewer 分工不等于可信身份；最终发布权限属于用户。

[架构](docs/architecture.md) · [完成链](docs/v4-completion.md) · [操作指南](docs/v4-operations.md)

## 三种模式的真实边界

| 模式 | 定位 | 限制 |
|---|---|---|
| `observe` | 未注册工作区的默认观察路径；受监督开发辅助 | 不是沙箱；无效输入、控制面目标等仍可能被拒绝 |
| `guarded` | 显式启用的受限原生文件编辑 | 不透明终端与子代理执行被拒绝，构建和验证由外部操作者驱动 |
| `strict` | 预留的强隔离等级 | 当前不可用，不应伪装成已实现 |

不要为了让任务继续而自动从 guarded 降到 observe。现阶段不以此处理生产凭据、
不可逆迁移、付款或无人审批发布。[生产准入与已知例外](docs/production-readiness.md)

## 与 Codex 如何联动

配套项目：[Codex Harness](https://github.com/JohnnyLiu597/codex-harness)。

采用**非对称验证**：

- Codex 自己完成普通任务：按风险选择必要检查，减少无关验证。
- Antigravity 执行或混合来源任务：保留完整强约束与 fresh evidence。
- Codex 审核 Antigravity 结果：不能因为审核者变成 Codex 就降低验收要求。

支持两种接力：

1. **未完成工作接力**：停止旧进程 → Release 并留下下一步 → 另一方 Acquire。
   保留严格策略、必需检查、失败证据和 unverified 状态。
2. **验收边界交接**：Antigravity 使用严格适配器，核对相同原生任务 ID，
   提供明确 NativeTaskRoot / DecisionPath，并重新运行原有 governed audit。

同一工作副本中，遵守协议的智能体只能有一个写者。真正并行修改用独立 worktree，
之后显式集成。共享文件不是权限来源，也不是 OS 级写锁。

[接力教程与命令](docs/codex-collaboration.md) · [协议边界](docs/agent-collaboration.md)

## 安装与验证

前提：Windows、Windows PowerShell 5.1、已安装并可使用的 Antigravity Desktop。
CLI、IDE、SDK 和 Desktop 不能仅因名称相近就被视为同一接口。

先阅读操作指南，在源码根目录预览：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File deploy/verify-package.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File deploy/test-v4-release.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File deploy/sync-to-runtime.ps1 -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File deploy/install-desktop-hook-plugin.ps1 -DryRun
```

检查目标后再执行安装：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File deploy/sync-to-runtime.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File deploy/install-desktop-hook-plugin.ps1
```

普通载荷与指定 Desktop plugin 是两个独立事务。保存各自的 transaction manifest，
按明确清单回滚，不按“最新备份”猜测。安装后仍要验证你的 Desktop 是否实际加载。
不要把安装检查或 synthetic fixtures 当成现场能力证明。

Skills 从同一源码进入 `.gemini/config/skills`，同时保留 `.gemini/skills` 兼容入口；
同名分歧拒绝导入，私有目录不会因迁移而被公开。[部署与恢复](docs/v4-deployment.md)

## 当前证据与未完成项

2026-09-10 本地工程验证曾通过24套回归，共享协议28项检查和两个已安装脚本入口的5项接力烟测。
这些数字是具体测试范围，**不是代码覆盖率、跨版本成功率或独立第三方认证**。
发布快照的实际检查结果以该快照对应报告为准。

仍未证明：

- 完整 OS 隔离、可信 checker 身份及所有工具路径覆盖；
- Antigravity 原生 Stop 在本机的新增激活；
- 两个 Desktop 界面的端到端现场切换；
- 真实图片／视频语义理解的完整正确性。

历史验收中存在缺 Post、可变证据引用等未闭环项，原状态保留，不能由新测试追溯改写为通过。

## 仓库内容与隐私

- `src/`：可维护规则、Skills、脚本、schema、测试与指定 hook 源码。
- `deploy/`：预览、包检查、事务安装、回滚与同步边界。
- `docs/`：设计、操作、证据边界和已脱敏的历史说明。
- `tests/`：确定性 fixtures；发布 fixture 使用合成标识，不携带原会话身份。
- `artifacts/`：本机运行记录与备份，默认不发布。

不包含凭据、auth/config 实例、会话数据库、原始聊天、浏览器状态或 plugin 下载缓存。
发布快照不携带包含个人路径的旧本地 Git 历史；原件保留在本地，而不是删除或伪造。

[安全边界](SECURITY.md) · [贡献方式](CONTRIBUTING.md) · [MIT License](LICENSE)
