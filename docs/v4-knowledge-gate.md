# v4.0 Knowledge Gate optional package

Status: implemented and locally tested in Windows PowerShell 5.1. Installed only
into isolated test fixtures. Real Obsidian installation is not authorized and was
not performed. Native image/video reading and independent semantic verification
remain blocked/unverified, respectively. No new model API, OCR, ASR or local AI.

## Artifacts and contract

| Artifact | Required content / gate responsibility |
|---|---|
| source-manifest.json | Original path, expected SHA256, media kind, duration and reliability |
| parser-observations.json | Original input IDs, output requirements, original-read capability, independently comparable observed hash, timestamps/transcript declarations |
| claim-ledger.json | Stable claim ID, original source ID, distinct fidelity/external truth, risk/action status, rejected/downgraded history |
| verifier-results.json | Per-claim supported/unsupported/uncertain result and evidence paths; high-risk rows mandatory |
| critic-results.json | Criticism type and evidence paths; no unsupported numeric/external claims |
| final-claims.json | Accepted claim IDs, all three surface mappings, required sections, links, attachments, completion time/publication status |
| test-result.json | Gate-generated mechanical/semantic/authority state, artifact hashes, independently computed original hashes, allowlisted issue codes |

Strict structural schemas reject extra fields, including Parser expected findings.
The bundled validator intentionally implements only the schema keywords actually
used by this package, not all of JSON Schema. The output result never contains raw
source text or transcript. Input artifacts are content artifacts and can be private;
they must not be copied into global Hook event logs or public source.

## Commands (from repository root)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/harness-evals/test-v4-knowledge.ps1
# Explicit isolated run that already contains the six populated inputs/originals:
& .\src\adapters\knowledge-gate\scripts\render-knowledge-surfaces.ps1 -FixtureRoot '<isolated-run>'
& .\src\adapters\knowledge-gate\scripts\invoke-knowledge-gate.ps1 -FixtureRoot '<isolated-run>'
# Explicit isolated fixture containing .knowledge-gate-fixture, not a real vault:
& .\src\adapters\knowledge-gate\scripts\manage-knowledge-package.ps1 -Action Install -FixtureRoot '<fixture>'
& .\src\adapters\knowledge-gate\scripts\manage-knowledge-package.ps1 -Action Diagnose -FixtureRoot '<fixture>'
& .\src\adapters\knowledge-gate\scripts\manage-knowledge-package.ps1 -Action Rollback -FixtureRoot '<fixture>' -TransactionId '<returned-id>'
```

The render command writes canonical body/card/diagram Markdown, preserving prior
outputs, then updates completion time. Re-run the gate after any input change.
It does not itself verify the evidence. Output identity is exact Final Claim Set
propagation; arbitrary narrative/diagram semantics remain out of scope.

Mechanical passes stop at `checking`. Unsupported source fidelity never becomes
external truth. All high-risk actionable/publishable content is conservatively
restricted because this package cannot attest independent external authority.
An uncertain high-risk claim is permitted in a non-actionable draft with a
per-claim Verifier row, ledger `status: downgraded` and `source_fidelity: uncertain`.
Every canonical surface carries an `[Uncertain]` marker. An uncertain Verifier
row cannot leave the ledger accepted/supported. Existing evidence files do not
make their contents true.

## Evidence and regression mapping

First RED: `artifacts/v4/knowledge-red/summary.json`, 0/23 passed because the requested
implementation was absent. First GREEN: `knowledge-green-01`, 23/23. Second RED:
`knowledge-red-02`, 23/25; input freshness and installer were missing. Second GREEN:
`knowledge-green-02`, 25/25. Later runs use unique folders and retain failed fixtures.
Third RED: `knowledge-red-03`, 25/27; embedded wiki links were not inspected and
the renderer could overwrite an original. Both reproductions were fixed;
`knowledge-green-03` passed 27/27. Final expanded verification:
`artifacts/v4/knowledge-green-final/summary.json`, 32/32 passed (Windows PowerShell
5.1), including all seven template schemas, output schema, renderer round-trip,
uncertain high-risk draft, malformed JSON, duplicate source IDs and ADS denial.
Package PowerShell static parsing also passed. No line/branch coverage is claimed.
Independent E review identified hardlink output aliases and incomplete uncertainty/
retired-wording propagation. Follow-up RED `knowledge-review-red` executed 37
cases with five expected failures (32/37). GREEN `knowledge-review-green` passed
37/37 under Windows PowerShell 5.1, including original byte-hash preservation
for a renderer hardlink and a Gate result hardlink, explicit uncertain ledger
downgrade, visible uncertainty on all three surfaces, and stale previous text.

| Requirements | Named regression cases |
|---|---|
| Duration/coverage/transcript | duration-overflow, unknown-duration-coverage, missing-transcript |
| Independent original hashing | false-observed-hash, copied-hashes-original-mutated |
| Truth / Parser contract | truth-dimension-mixing, parser-prefilled-conclusion |
| High-risk / critic | high-risk-missing-verifier, high-risk-uncertain-action, critic-unsupported-number |
| Final set / propagation | final-rejected-claim, card-inconsistent-reference, downgraded-old-wording |
| Links / structure / freshness | broken-wiki-link, missing-attachment, missing-section, modified-after-completion, future-completion, changed-input-after-completion |
| Identity / paths / capabilities | cross-task-artifact, escaping-original, image-native-unavailable, video-native-unavailable |
| Install / fault / rollback | package-install-failure-rollback |
| Renderer safety / embedded references | renderer-original-protection, embedded-broken-wiki-link |
| Schema / positive uncertainty / edge cases | schema-template-render-roundtrip, uncertain-high-risk-draft, ads-original-denied, duplicate-source-id, malformed-json-visible |
| Independent-review closure | renderer-hardlink-original-protection, gate-result-hardlink-original-protection, uncertain-verifier-with-certain-ledger, uncertain-canonical-visible, previous-wording-still-current |

The counts are executed regression cases, not coverage percentages. Line/branch
coverage is unmeasured. The fixed text fixture tests machinery, not objective
knowledge correctness. Image/video fixtures explicitly exercise unavailable
capability with synthetic metadata; actual media understanding was not tested.

## Remaining limits

- Canonical rendering checks exact claim propagation, not semantic paraphrase.
- Native-reader and verifier fields are declarations, not trusted actor identity.
- Evidence existence/hash does not verify the Critic's external statistics.
- Timestamps are same-user metadata; hashes bind this run, not immutable history.
- Paths reject traversal, ADS, ambiguous suffixes and reparse points, but cannot
  eliminate same-user TOCTOU; this adapter is not an authorization boundary.
- Package-local Windows file identity checking rejects multiply-linked files;
  an unsafe output path throws rather than replacing original/evidence bytes.
  The check remains point-in-time and does not eliminate concurrent alias races.
- Retired wording is a literal substring check across current claims/surfaces,
  including rejected claim text. It is conservative (quotes/negations can also
  fail), not a semantic paraphrase or fact verification model.
- Installer catches switch/postcheck exceptions and retains old/failed payloads;
  sudden process/power loss can require manual recovery. No crash-safe claim.
- Real vault integration requires separate authorization and an actual original-
  reading desktop acceptance run. Never bulk-remediate old notes as "verified".
