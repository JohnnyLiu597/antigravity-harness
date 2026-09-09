# Antigravity Evaluation Conversation Protocol

Independent behavioral cases require fresh conversations. Reusing one chat
allows earlier Skill names, corrections, tool results, and expected answers to
contaminate later cases.

## Use A New Conversation For

- Tier 0 versus Tier 1 routing comparisons;
- baseline versus candidate harness comparisons;
- adversarial or negative cases;
- pass@1/pass@3 repetitions;
- an independent Reviewer or Checker;
- testing whether the router discovers a Skill without being told its name.

Use the same workspace only when its starting state and fixture hashes match.
Record model policy, permissions, network policy, timeout, and prompt hash.

## Keep The Same Conversation For

- planning, execution, retries, and recovery for one logical task;
- Attempt Ledger continuity;
- user clarification that changes the same task contract;
- resuming the same job from its durable state.

## Evidence Rule

If a prior turn named `reliable-maker-control`, an ensuing routing test cannot
prove autonomous discovery. Classify it as context-contaminated and rerun in a
fresh conversation without naming Tier 1, the router, or the Skill.

Self-reported independent roles remain unverified even across separate chats;
fresh context improves checker independence but is not cryptographic identity.
