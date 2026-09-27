"""Focused static contract guards for the native final-acceptance entrypoints."""
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require(text: str, needles: tuple[str, ...], label: str) -> None:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise AssertionError(f"{label} is missing fail-closed contract text: {missing}")


def main() -> None:
    complete = (ROOT / "tools/Complete-DevFleetInternalAcceptance.ps1").read_text(encoding="utf-8-sig")
    authority = (ROOT / "tools/Update-CurrentReleaseAuthority.ps1").read_text(encoding="utf-8-sig")
    builder = (ROOT / "tools/Build-AIAuditBundle.ps1").read_text(encoding="utf-8-sig")
    validator = (ROOT / "tools/validate_release_bundle.py").read_text(encoding="utf-8-sig")

    require(complete, (
        "--check pre-acceptance", "Test-PrivateAuthenticodeSignature",
        "84b7d8b8-ee6c-4085-aa29-4b0adc316de2", "DevFleet-E2E-Win11-01",
        "DevFleet-E2E-Linux-01", "FINAL-ACCEPTANCE.json",
        "--check final-acceptance --final-record $pendingFinalPath",
        "Move-Item -LiteralPath $pendingFinalPath -Destination $finalPath -Force",
        "status='BLOCKED'", "INTERNAL_ACCEPTANCE_BLOCKED",
        "validation_evidence_current' $false", "internal_promotion_allowed' $false",
        "public_promotion_allowed' $false",
    ), "completion tool")
    require(authority, (
        "--check final-acceptance", "$finalAcceptanceValid",
        "validationEvidenceCurrent = $finalAcceptanceValid",
        "internalPromotionAllowed = $finalAcceptanceValid",
        "$releaseEligible = $finalAcceptanceValid",
        "$mutableState.internal_promotion_allowed=$finalAcceptanceValid",
        "$mutableState.public_promotion_allowed=$false",
    ), "authority updater")
    require(builder, (
        "PreAcceptanceReleaseAudit", "--check release-evidence",
        "--mode $releaseValidationMode", "pre-acceptance",
        "release-audits", "CURRENT-RELEASE-AUDIT.json",
        "devfleet-pre-acceptance-release-audit-v1",
        "releaseEligible=$false", "internalPromotionAllowed=$false",
    ), "audit builder")
    require(validator, (
        '"pre-acceptance"', "validate_final_acceptance",
        "CURRENT-STANDARD-TOKEN.json", "FINAL-ACCEPTANCE.json",
        "REAL-USE-ACCEPTANCE", "U01", "U05",
        "pre-acceptance audit contains post-audit evidence (cycle)",
    ), "release-bundle validator")
    if authority.find("--check final-acceptance") > authority.find("$candidateFlags ="):
        raise AssertionError("authority reads candidate promotion flags before validating FINAL-ACCEPTANCE")
    staged = complete.find("Write-AtomicJson $pendingFinalPath $final")
    validated = complete.find("--check final-acceptance --final-record $pendingFinalPath")
    published = complete.find("Move-Item -LiteralPath $pendingFinalPath -Destination $finalPath -Force")
    if min(staged, validated, published) < 0 or not staged < validated < published:
        raise AssertionError("completion tool must stage, validate, then atomically publish FINAL")
    if "Write-AtomicJson $finalPath $final" in complete:
        raise AssertionError("completion tool publishes FINAL before independent validation")
    print(json.dumps({"status": "PASS", "checks": 4}, sort_keys=True))


if __name__ == "__main__":
    main()
