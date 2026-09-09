# Antigravity Harness v4 生产准入与收尾

## 结论

**ReadyForScopedProduction：仅限受监督、低风险、可回滚的内部工程辅助。**
这是有条件的维护者准入判断，不是 Completion Gate 的 verified、OS 隔离或
无人值守生产的证明。本轮功能冻结。没有替新业务项目启用 guarded 或执行业务发布。

| 独立状态 | 结果 |
|---|---|
| ScopedProductionReady | true，仅限下述范围 |
| AcceptanceAttemptTerminal | true，两次验收 Attempt 均 stopped |
| SpecifiedDesktopScenariosObserved | true，五阶段及终端/ADS 拒绝有现场证据 |
| CanonicalCompletionClosed | **false**，缺少最终 Claim/Envelope，第一 Attempt 历史证据已过时 |
| CompletionGateReadOnlyStatus | **unverified**，实际返回 claim-missing |
| CheckerAuthority | unverified |
| HookSessionAudit | warning，保留 missing Post |
| RuntimePayloadChangedInCloseout | false，不重装、不重跑桌面 Canary |

## 可用范围

**默认 observe：日常开发辅助。** 适合可信操作者监督下的代码阅读、开发、构建和
测试，产物仍需项目验证。不保证永不拦截：无效输入、控制面目标、精确 sentinel、
重复准入，以及变更/不透明工具发生日志故障时，仍可能 deny。未注册工作区默认
observe；Hook 不是所有工具的全局拦截器，观察不是沙箱或敏感数据隔离。

**可选 guarded：低风险原生文件编辑。** 仅用于明确注册、Contract/Binding
路径内、可回滚的受监督修改。受保护会话的 run_command 与不透明子代理不可用；
构建、测试、状态迁移和完成验证由外部操作者驱动，不是自动化全栈开发模式。
同用户恶意/任意执行、未观察工具和 Hook 到实际写入间的路径竞态没有 OS 隔离。
不据此处理生产凭据、不可逆迁移、付款、无人审批发布等高风险任务。

strict 当前 unavailable。原生 Stop 未接入/未现场验证；不推断宿主尚未开放接口。
知识机械检查已测试，真实图片/视频语义未验证；原件不可读就 blocked。不把可信
模型签名接口新增为一般多模态读取前提，也不编造模型身份认证。

## 实际完成的收尾

- 复用原 Run ID、TaskId、TaskRoot 和宿主会话，没有重建身份掩盖历史。
- acceptance-01 保持 stopped，完整记录哈希未改变。
- acceptance-02 通过标准更新器关闭为 stopped，绑定固定 resumed 文件快照；
  未填写虚构的原生命令退出码。
- Binding 保持 revoked / revision 3，没有解封或扩大工作区权限。
- 标准 Report 生成成功，report_status 为 stopped，不是 passed。
- 只读 Completion Gate 实际返回 unverified / claim-missing；governed audit
  返回 failed / decision-reference-required。没有捏造 Claim/Envelope 冒充通过。
- 76 个普通载荷和 7 个插件文件与安装版本一致，明确引用的 21/21 套件结果复用。
- 26 项确定性收尾检查通过，验证关闭、保留、哈希和状态真实性，
  **不替代完整任务 Completion Gate**，不代表覆盖率。

## 例外与处置

### E1：step 8 缺 Post

原事件保持 unresolved。已知的是一次文件读取失败报告和缺 Post，不能仅凭现象
确定 cortex/宿主哪层没有派发；本轮未读 transcript 或应用内部代码确认根因。
本次七个明确准入场景独立判断，不把该读取算成功；要求每次调用都闭环的负载不
在此次准入范围内。

整个会话还包含后续维护尝试：37 Pre、29 Post、7 denied、28 completed、
1 failed、1 unresolved、0 orphan。不要与 step 36 截止的验收窗口混报
（14 Pre、8 Post、5 denied、1 unresolved）。新增失败与拒绝同样保留。

### E2：第一 Attempt 的可变证据引用

acceptance-01 当时记录的 bound 输出哈希以 f3a34c 开头；evidence_artifact
仍指向 output.txt，当前 resumed 哈希以 6f2616 开头。Gate 重验所有 Attempt
证据，因此该历史任务不能宣称完整闭环。

不改旧记录或哈希，不按已知文本重建原件，不排除它来制造 Gate 成功。
此缺口阻断该历史任务的 canonical completion，不否定已独立观察的准入行为。
后续新任务必须先保存固定证据，再结束 Attempt；本轮不为美化旧链追加版本。

### E3：revoked 被测会话不负责维护控制面

后续 step 60 命令及 step 76 写入均被拒绝；Created/Ran 标签不是成功证明。
收尾已在外部执行环境完成，不能靠解除撤销让被测代理自授权。

## 操作与验证

使用源码根目录外部 Windows PowerShell 5.1，遵循 [v4 操作指南](v4-operations.md)。
具体业务项目必须由操作者明确选定。

顺序：选模式 → 注册/复用 TaskRoot → Contract → running Attempt → 必要时绑定真实
会话 → 实现 → 外部实际验证 → 固定证据快照 → 结束 Attempt → 完整 Report/Claim/
Envelope → 明确 DecisionPath 审计。

验证不通过就保留失败。必须结束但未验收的 Attempt 使用 stopped/blocked，不是
passed。实际 Gate 为 checking 时也不得升级 verified。撤销不会结束 Attempt，
两者分别管理；改成 observe 是放宽准入，必须是明确操作。

禁用和双事务精确回滚见 [发布记录](v4-release.md)，不要按时间挑最新备份。
本轮无需重装/回滚。反向导入不是完整事务，Refresh 后失败可能需人工恢复。

## 证据入口

- `artifacts/v4/production-closeout/before-close.json`：关闭前状态、事件/载荷哈希。
- `artifacts/v4/production-closeout/after-close.json`：关闭后快照与固定证据引用。
- `artifacts/v4/production-closeout/canonical-status.json`：真实 Report、只读 Gate/audit。
- `artifacts/v4/production-closeout/checks.json`：26 项收尾不变量结果。
- `artifacts/v4/production-closeout/review.md`：独立审查。
- `artifacts/v4/production-closeout/readiness.json`：机器可读准入判断。

## 非阻断 backlog：本轮不实施

- 调查缺 Post 真正原因；保持原事件，不补回调。
- 后续任务统一固定证据快照，不追溯美化旧链。
- 仅在有明确需求/授权时研究 OS 隔离、原生 Stop 和可信身份边界。
- 获得真实原件再做正向媒体语义评估；真实 Obsidian 安装仍需单独授权。

本轮收尾后停止工程扩展，仅由真实、可复现的使用阻断问题触发修复。
