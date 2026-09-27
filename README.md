# DevFleet
DevFleet is a self-hosted platform for isolated local development work using AI coding agents, offering optional redundancy with added nodes.

DevFleet v1.2.13 configures isolated Windows-hosted development compute, Surrogate/failover and append-only Vault workflows, with a Python/Linux dashboard and a .NET WPF installer.

**Current certification: INCOMPLETE. This repository import does not claim a certified release.**

- [Build from a clean clone](BUILD-FROM-CLONE.md)
- [Product guide](source/README-FIRST.md)
- [AI certification handoff](ai/CERTIFICATION-HANDOFF.md)
- [ChatJimmy entrypoint under 50,000 bytes](ai/CHATJIMMY-START-HERE.md)
- [Complete source text and index](ai/INDEX.md)
- [Release completion requirements](docs/ai/devfleet-release/DONE.md)
- [Source import provenance](ai/GITHUB-IMPORT.md)

The installer payload is included. Dependencies, licensed guest images, private credentials and signing keys must be provisioned separately. See the build guide for environment requirements. Original source modes/hashes are in `ai/ORIGINAL-SOURCE-INVENTORY.json`. A fresh import has a new Git commit identity and does not inherit the original host's certification authority.
