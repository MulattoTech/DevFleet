# GitHub source import

The owner authorized uploading the prepared source to https://github.com/MulattoTech/DevFleet and making the repository public on 2026-09-27.

This import extends the repository's existing initial commit a668dfc7bb8796e78d2bbb432c87a70ec45f8287. Its original README description is preserved. No history is force-replaced.

## Source provenance

- Original certification checkout HEAD: `110fc2ee4fe611518e302b0185e9499a8e8a7e40`.
- Original standalone complete audit ZIP SHA-256: `236d8de6e929f5b0998954be7279ee52549569f5079c1081fd77fb2221106669` (80,835,299 bytes).
- 968 original tracked source/tooling/documentation files, including the installer payload, are preserved with recorded hashes/modes in `ORIGINAL-SOURCE-INVENTORY.json`.
- Added README/build/upload/AI documentation explains the imported tree. The GitHub commit identity is different from the original certification checkout. Some original files normalize CRLF to LF under the inherited Git attributes; the source verifier checks the recorded normalized hash explicitly.
- The sibling machine-specific evidence, signed test artifacts and full native audit ZIP remain in the standalone handoff package. They are not automatically public with this source import.

## Reading the project

Start with [ChatJimmy guide](CHATJIMMY-START-HERE.md), [complete source index](INDEX.md), [certification handoff](CERTIFICATION-HANDOFF.md), or [build guide](../BUILD-FROM-CLONE.md). The ChatJimmy guide is below 50,000 UTF-8 bytes. Each source part is also below 50,000 bytes. Retrieval and model context limits still apply.

## Certification

Status remains **INCOMPLETE**. The original native audit passed diagnostic validation with `PASS_WITH_BLOCKER`, `releaseEligible=false`; no GitHub upload can award proof or release credit. Publication of this source does not change native publicPromotionAllowed/publicPublisherTrust flags, provide a signing key, or certify a clone-built artifact.

`GITHUB-UPLOAD.md` is the original standalone package's manual import guide. This repository already contains that import; do not repeat its git-init instructions inside this clone.
