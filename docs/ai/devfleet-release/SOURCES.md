# Provenance and design boundary

## Supplied evidence, not a fresh live inspection

- `DEVFLEET-AI-OPERATING-RULES.md`
  SHA-256: `00273b4c777b4d4bd9cb985ac07383d1a5e4f8ab7abd91633a28a30ccc6bdded`
- `DEVFLEET-KNOWN-EDGE-CASES.md`
  SHA-256: `532cc1f520d2cd7ac5c329d7d21145212e8f25dd38e0ba5edbfc9f266fc8b296`
- `Codex_CLI_Output_(DevFleet)_Updated-9-5-26-458PM.md`
  SHA-256: `af8a160054ee2bf51802473d04966cd2535c38a16236679c5417cbe5f5f57853`
- `DevFleet-v1.2.13-AI-Audit-LATEST(20260905-215907).zip`
  SHA-256: `5c5154c4257d5852b532a3b465b95e865fcbe07892c505f30883b7219b6becca`

Relevant members of the latest audit: CURRENT-CANDIDATE.json;
audit/AFTER-ACTION-REPORT.md; audit/NEXT-CODEX-HANDOFF.json;
audit/SOL-HELPER-ALLOCATION-LEDGER.json; audit/SOL-HELPER-FINDINGS.json;
evidence/campaigns/wpf-no-report-20260905-ledger.json; current driver/contract/test files;
source/tools/release_fingerprint.py; source/docs/03-DAILY-USE.md; source/docs/04-RECOVERY.md.
Archive `release-tooling/` may represent native `tools/` files. Live paths are verified before use.

Historical safeguards and exact resource/signing identities derive from the supplied operating
contract. Seed current values and local test counts derive from the latest uploaded records;
no live Windows validation is claimed by this package. Earlier snapshot values remain historical.

## Newly designed workflow in this package

Milestone S0–S5 organization, DF-STABLE-20260905-A with three renewed readiness invocations
and two shared corrective replays, memory file organization/update triggers, U01–U05 acceptance
mapping, installer behavior and feature-handoff structure are proposed implementation choices
for the user's requested approach. Explicit user adoption makes the revised workflow active.
They are not rules or results discovered in the old audit. All native release gates are retained.

U01–U05 use the shipped daily-use/recovery semantics but are not claimed to be existing complete
E2E tests. Read the live operation contracts before implementing/checking them. Existing docs'
production-instance example commands are not authorized targets for disposable testing.

## Official Codex integration references checked September 5, 2026

- AGENTS.md discovery and precedence:
  https://developers.openai.com/codex/agent-configuration/agents-md
- Skill metadata, explicit invocation and progressive disclosure:
  https://developers.openai.com/codex/build-skills
- Repository-local skills pattern:
  https://developers.openai.com/blog/skills-agents-sdk

Root AGENTS receives only a compact routing block. A nonempty existing AGENTS.override.md
has precedence, so the installer appends the block there instead of creating a shadowing
file. Existing text is preserved. Skill lives under .agents/skills/devfleet-release-control/.
No new global Codex configuration or model selector is installed. Runtime availability and
permissions are still checked in the resumed session.
