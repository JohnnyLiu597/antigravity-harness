# v4 plugin deployment and recovery

## v4 reverse import boundary

`sync-from-runtime.ps1` now plans imports before writes, rejects private roots and
targets, skips nested private source subtrees, rejects reparse/hardlink/undeclared
ADS paths, and validates Refresh moves before changing source. Its focused owner is
`deploy/test-v4-runtime-import.ps1` (12 Windows PowerShell 5.1 cases). Real runtime
import was not performed during this release. Reverse import is not a fully
transactional or isolated operation: Refresh retains a backup, but a subsequent
copy failure can require explicit manual restoration of that backup. Do not
describe its scope as the same guarantee as the forward installers.

Normal forward sync also refuses a root `.gemini-private` marker for both install
and rollback, and validates alternate streams during every content-hash check.
Only the main stream and optional Zone.Identifier are admitted. Added regressions
are in the now 12-case `deploy/test-v4-runtime-sync.ps1` owner.

The existing `deploy/install-desktop-hook-plugin.ps1` is the stable plugin entry
point. It does not install the ordinary runtime payload; use the existing
`deploy/sync-to-runtime.ps1` transaction separately. There is no second plugin
framework, application patch, new account, service, or elevated boundary.

```powershell
.\deploy\install-desktop-hook-plugin.ps1 -DryRun
$install = .\deploy\install-desktop-hook-plugin.ps1 | ConvertFrom-Json
.\deploy\install-desktop-hook-plugin.ps1 -Mode Diagnose
.\deploy\install-desktop-hook-plugin.ps1 -Mode Disable
.\deploy\install-desktop-hook-plugin.ps1 -Mode Enable
.\deploy\install-desktop-hook-plugin.ps1 -Mode Rollback -RollbackManifest $install.transaction_manifest
```

Save each successful transaction manifest path before proceeding to another
deployment. Rollback is explicit: never select a recovery source by modification
time. The compatibility `-RollbackManifest` alone also selects Rollback mode.
Enable and Disable are staged, recoverable changes of the existing hook owner
flag. They require a structurally valid installed plugin; if files are corrupt,
use the retained transaction and explicit recovery after inspecting the damage.
An already running desktop process may cache hook configuration: static Disable
is not proof that the host has unloaded hooks. Close/restart the host when needed.

## Transaction protocol

1. Admit only the exact named production plugin, or an isolated system TEMP
   `antigravity-<name>-<32 hex GUID>/plugins/antigravity-reliable-control` target.
2. Acquire an exclusive file handle in the plugin-specific backup store. Busy
   operations fail immediately; process termination releases the OS handle.
3. Hash the candidate and current file sets; create an fsynced v2 journal.
4. Copy candidate into `stage`, validate identity, hook-relative commands,
   bounded timeouts, JSON, PowerShell syntax, exact file set and SHA-256 hashes.
5. Persist switching intent, rename the active directory to `previous`, then
   rename the validated stage into the active plugin location.
6. Repeat structural and hash checks after the switch, then persist installed.
7. On a caught failure restore the prior directory (or original absence), retain
   failed candidate/stage and journal revisions, and return a failure.

All state is under the plugin-specific
`.gemini/config/plugin-backups/antigravity-reliable-control/<transaction-id>`
store. Only the named plugin directory is switched. No whole-config copy,
unrelated plugin mutation, credential inspection, or private session copy occurs.
The v2 journal stores local paths, timestamps, action/status, file-relative paths,
and hashes; these deployment records are private local artifacts, not distributable
source. It contains no hook payload, command arguments, stdout, transcript, or auth.

Reparse points are rejected in ancestors and recursively encountered children;
enumeration does not descend into them. Ambiguous device/ADS paths, arbitrary
network roots, and non-Zone.Identifier alternate streams are rejected. Payloads
are limited to 512 files, 128 queued directories, and 16 MiB. Hook commands are
plugin-relative `.cmd` entries with a 1-30 second declared timeout. This installer
parses scripts; it does not execute candidate code to validate its own authority.

## Interrupted switch

Windows does not provide a single atomic exchange of two populated directories
here. A hard process/OS interruption between the two renames can temporarily
leave the active plugin absent. It does not leave a mixed old/new directory.
`Diagnose` returns `recovery-required` with explicit pending manifest paths;
another install refuses to proceed until explicit rollback resolves the journal.

```powershell
$diagnosis = .\deploy\install-desktop-hook-plugin.ps1 -Mode Diagnose | ConvertFrom-Json
# Review the specific pending transaction; pass that exact path, not a guessed latest backup.
.\deploy\install-desktop-hook-plugin.ps1 -RollbackManifest $diagnosis.pending_transactions[0]
```

Rollback validates manifest location, target identity, fixed stage/previous paths,
snapshot entries, prior hashes, and active candidate hashes before displacement.
The displaced candidate is retained. Repeated completed rollback is idempotent.
Corrupt journals, changed backup contents, unexpected current versions, unavailable
disk, permissions, or open files may prevent automatic recovery; the tool stops
instead of overwriting uncertain state. Retained artifacts support operator review.
Historical v1 manifests remain untouched but are not accepted by v2 rollback
because they do not carry trustworthy prior snapshots. A first v4 install captures
the existing v3 payload as a v2-recoverable previous version.

## Evidence and limits

`Diagnose` is read-only and reports busy, not-installed, healthy (structural checks),
invalid, or recovery-required. Healthy is not an installed-source fingerprint or
live desktop activation attestation. Every result explicitly keeps live desktop
verification false. Installation/postchecks, simulated interruption, and desktop
canaries are separate evidence layers.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\harness-evals\test-v4-deployment.ps1
```

Tests preserve isolated TEMP fixtures and report their location. They exercise
install/rollback/enable/disable, stale files, malformed JSON/syntax/commands, ADS,
junctions, wrong targets, forged manifests, altered backups, exclusive locking,
three caught-failure positions, and a durable interrupted-rename simulation.
This is requirement-case evidence, not measured code coverage or a physical
power-loss test. Native host reload and same-user hostile racing remain unverified.

History has no automatic deletion or rotation. Each deployment retains the prior
payload plus small journal revisions; failed stages add candidate-sized storage.
Budget up to roughly two payload copies per transaction plus metadata (payload
admission cap 16 MiB). Operators must inspect capacity and archive outside active
plugin discovery explicitly. No default permanent cleanup is performed. The lock
coordinates this installer only: same-identity processes can still tamper or race
filesystem checks, hashes are not signatures, and rechecks do not eliminate TOCTOU.

## Normal runtime transaction

`deploy/sync-to-runtime.ps1` separately stages normal payload files, checks JSON,
PowerShell syntax and hashes, takes validated before-image backups, and switches
each file atomically before a complete post-install hash pass. It deliberately
does not load/run scripts during staging: scripts that resolve the desktop plugin
require the parent integration check with both normal runtime and plugin present.
The optional `src/adapters` packages remain excluded from the global sync plan.

`-NoBackup` is now refused. A custom `-TransactionRoot` must be a new immediate
runtime child named `backup-<id>-antigravity-harness-sync`; external transactions
and manifests are refused. The existing v2 normal-runtime manifest format remains
supported, with stricter validation of target paths, exact backup mapping, private
markers, current hashes, root/ancestor/leaf reparse points, and backup hashes.

Rollback preserves both newly installed and replaced candidates under the
transaction's `displaced/<id>` directory; the legacy JSON `removed_files` field
counts files removed from active runtime, not permanently deleted files. Empty
directories and failed staging/journal revisions remain retained. A normal-runtime
named mutex fails immediately on contention. It is local-session and path-derived,
not a security boundary against a same-user process or alternate path spelling.

Each file exchange is atomic, but the entire multi-file runtime is not one atomic
filesystem transaction. A hard interruption may leave multiple versions across
different files until explicit rollback. A subsequent install refuses an unfinished
owned manifest. Recovery is manifest-directed and can stop if current files differ
from both installed and prior hashes. Do not edit the runtime during deployment.

Focused regression: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File
.\deploy\test-v4-runtime-sync.ps1`; existing bidirectional boundaries remain tested
by `deploy/test-sync-boundaries.ps1`. Both suites retain their TEMP fixtures.
