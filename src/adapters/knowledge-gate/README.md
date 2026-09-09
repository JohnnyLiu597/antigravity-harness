# Knowledge Gate optional adapter (Antigravity Desktop)

This package is opt-in. It does not install global agent rules and never updates
real knowledge items, Obsidian settings, originals or prior run history.

The six input JSON templates and the generated `test-result.json` have matching
schemas. Copy templates into an isolated run directory, supply originals and
evidence, and invoke `scripts/render-knowledge-surfaces.ps1` followed by
`scripts/invoke-knowledge-gate.ps1`. Templates are not completed evidence.

Parser input: original source paths/IDs and output requirements only. Do not give
the Parser expected findings or conclusions to reproduce. Read the original with
an actually available native tool/model. If it cannot read the original, report
`original_read: false`, `capability: unavailable`; the gate returns blocked.
The text sample is synthetic; the image/video descriptors are negative capability
fixtures, not decoded media or semantic evidence. No OCR/ASR/model/API is bundled.

The Verifier examines each high-risk claim and may return uncertain. Critic
findings that introduce statistics, empirical examples or external facts need
evidence paths. Presence of those files proves neither correctness nor independent
identity. A model review is still required to assess the evidence and semantics.
An uncertain Verifier result requires the corresponding ledger claim to be
`downgraded` with `source_fidelity: uncertain`. The canonical renderer visibly
prefixes uncertain/downgraded claims with `[Uncertain]` on every surface; merely
changing the Verifier row cannot leave an accepted/supported claim unchanged.

The gate independently hashes original bytes and compares both expected and
parser-observed hashes. Hash agreement is integrity, not an identity signature,
proof of semantic reading, or external truth. `source_fidelity` and
`external_truth` remain separate. External verified authority is unavailable;
high-risk actionable claims and publishable status are conservatively rejected.

All body/card/diagram outputs must exactly match the canonical Final Claim Set
renderer. Rejected and unsupported claims cannot enter that set. This is a narrow
Markdown interchange format, not a general validator for arbitrary prose,
Mermaid, raster diagrams, or existing vault content. Semantic equivalence and
unlabelled fact invention remain model checks, never mechanically verified.
Literal retired text from `previous_text` and rejected claims is forbidden in
current claims/rendered surfaces. This deliberately conservative substring check
is not semantic paraphrase detection and can also reject quoted/negated old text.

Install operations require an explicit fixture root containing
`.knowledge-gate-fixture` and reject a root containing `.obsidian`. Only the
`.knowledge-gate` subtree and `.knowledge-gate-transactions` are managed. Install
stages, hashes, switches and checks; exceptions restore the old package. Rollback
requires the exact current installation transaction ID. Previous and failed
payloads are retained. No permanent delete, no real-vault install in this release.

The adapter is same-user mutable and does not establish OS isolation. Checks are
point-in-time; concurrent mutation/reparse races are not a trusted boundary.
Existing files with multiple NTFS hardlinks are rejected by a package-local
Windows file-handle identity check, including originals, renderer destinations,
evidence and test-result output. If an output path is unsafe the command throws
without replacing that path, even with the Gate's `-NoThrow` switch. Unusual file
identity/access errors also fail closed; no OS-level tamper resistance is claimed.
Unexpected process termination during a switch may need manual recovery from the
retained `previous`/`staging` directories; the installer is exception-recoverable,
not a crash-safe filesystem transaction. Do not run it against a live vault.

Result states: `failed` = mechanical violation; `blocked` = unavailable original
reading; `checking` = mechanical checks passed, semantics/authority unverified.
Prior test results are preserved as uniquely named JSON before replacement.

See the source repository's `docs/v4-knowledge-gate.md` for commands and evidence.
