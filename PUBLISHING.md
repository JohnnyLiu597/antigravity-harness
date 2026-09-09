# Publishing this snapshot

Repository: https://github.com/JohnnyLiu597/antigravity-harness

This publication starts from a sanitized snapshot rather than importing the
original local Git ancestry. The older local history contains personal machine
paths and remains preserved privately. Do not push that history into this remote
or force-push it over the clean main branch.

The snapshot excludes runtime state, raw sessions, private backups and local test
reports. Historical documentation uses anonymous references. The v351 fixture is
a synthetic public correlation shape, not an original host transcript.

For future releases, prepare a new reviewed delta against this clean history,
check privacy in all publishable roots (not only src), rerun affected tests, and
push normally. A package check that scans src alone does not clear root docs,
test fixtures or prior Git history for publication.

The original installed runtime is not changed by documentation publication.
