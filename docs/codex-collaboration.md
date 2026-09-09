# 与 Codex 联动：接力而不降低验收

配套：[Codex Harness](https://github.com/JohnnyLiu597/codex-harness)。
两套运行时独立，共享的只是项目任务、写入归属、下一步和明确证据引用。
不复制对方的 auth/config/会话，不创建额外调度器，不伪造原生工具回调。

## 工作分配

| 场景 | 推荐职责 | 验证要求 |
|---|---|---|
| Codex 规划、Antigravity 执行 | Codex 给目标、范围和验收条件；Antigravity 在约束内实现 | Antigravity 完整强验证 |
| Antigravity 执行、Codex 审核 | Codex 看实际 diff 和明确引用，处理缺口 | 不降级，不以 Codex 的普通轻量检查替代原生完成链 |
| 两方交替处理未完成工作 | 先停旧进程，Release，另一方再 Acquire | 保留 unverified、失败证据和严格来源 |
| 两方同时修改 | 独立 worktree、明确文件责任，之后显式集成 | 集成后的相关检查必须重新验证 |

## 共享状态

状态位于项目的 artifacts/agent-collaboration/<task-id>/，应被 Git 忽略。
task.json 是机器入口；handoff.md 由脚本生成。required_checks 是检查标识，不是
交给执行器盲目运行的任意命令。会话引用被哈希；owner token 只是协调标识，不是凭据。

Antigravity 被选为写者后，来源保留；verification_policy 不会在返回 Codex 时降低。
共享 acceptance_status 始终 unverified，RecordEvidence 只登记 reference-only。

## 最小操作示例

从一个已明确身份与范围的项目开始。使用现有原生逻辑 task ID，不为掩盖失败创建新身份。
先安装两套 harness，然后在 PowerShell 中操作：

```powershell
$project = '<existing-project-directory>'
$cx = Join-Path $env:USERPROFILE '.codex/scripts/invoke-agent-handoff.ps1'
$ag = Join-Path $env:USERPROFILE '.gemini/scripts/invoke-antigravity-handoff.ps1'
$state = & $cx -Action Init -ProjectRoot $project -TaskId parser-fix -Engine codex -Objective 'Fix parser behavior' -AllowedPaths 'src/parser.ps1' -RequiredChecks parser-unit | ConvertFrom-Json
$state = & $cx -Action Acquire -ProjectRoot $project -TaskId parser-fix -Engine codex -SessionRef 'cx-session' -ExpectedRevision $state.task.revision | ConvertFrom-Json
# Codex performs the bounded planning/work, then stops all its write processes.
$state = & $cx -Action Release -ProjectRoot $project -TaskId parser-fix -Engine codex -SessionRef 'cx-session' -Token $state.task.writer.token -ExpectedRevision $state.task.revision -NextAction 'Continue implementation; preserve strict native verification' | ConvertFrom-Json
$state = & $ag -Action Acquire -ProjectRoot $project -TaskId parser-fix -SessionRef 'ag-session' -ExpectedRevision $state.task.revision | ConvertFrom-Json
```

这只演示共享归属。它没有创建 Antigravity Contract、Attempt 或 Binding，也没有授予
guarded 终端权限。原生操作仍按 [v4 操作指南](v4-operations.md)完成。

## 未完成交接与验收交接必须分开

**未完成接力**：Release 后另一方可以 Acquire，不需要把任务先包装成“通过”。
写清 NextAction；过时或失败的证据照常保留，严格策略不会变轻。

**验收边界 Handoff**：Antigravity 适配器要求明确 NativeTaskRoot 和 DecisionPath，
匹配同一逻辑任务，并由既有 governed audit 重新调用原 Completion Gate。
缺失或过时证据会阻止这种 Handoff；即便本地链条有效，也不能自称具有可信 checker 身份。

## 冲突与中断

- 每次变更使用刚读取的 revision；冲突后重新读取，不覆盖别人的状态。
- 同一 checkout 只有一个协议写者。过期租约不能自动抢占；先确认旧进程已停止。
- 共享锁不是 OS 沙箱，无法约束绕开协议的任意进程。
- 更换工作树或合并后重新确认项目身份与证据新鲜度，不透明搬用旧通过结论。
- 本项目不启用跨任务自动跳检缓存；不以摘要、模型自述或原生 Post 冒充完整验收。

脚本级接力回归不等同于两个 Desktop 界面的现场切换；后者需要在具体安装版本上验证。
