"""The unattended pairing seam must never turn a passphrase into transport text."""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
COMMON = (ROOT / "windows" / "DevFleet.Common.psm1").read_text(encoding="utf-8")


def bundle_function(name):
    start = COMMON.index(f"function {name} {{")
    end = COMMON.index("\nfunction ", start + 1)
    return COMMON[start:end]


def test_bundle_helpers_accept_securestring_without_a_plaintext_transport():
    for name in ("New-EncryptedBundle", "Expand-EncryptedBundle"):
        body = bundle_function(name)
        assert "[Security.SecureString]$Passphrase" in body
        assert "$null -eq $Passphrase" in body
        assert "Read-Host" in body and "-AsSecureString" in body
        assert "else { $Passphrase }" in body
        assert "$env:" not in body
        assert not re.search(r"(?:ArgumentList|Arguments|StandardInput).*\$(?:password|Passphrase)", body, re.I)
        assert not re.search(r"(?:Write-Host|Write-Output|Write-Warning|Set-Content|WriteAllText).*\$(?:password|Passphrase)", body, re.I)
        assert "$password=$null" in body


def test_desktop_export_forwards_securestring_and_retains_unconfigured_deferral():
    source = (ROOT / "windows" / "10-Export-Desktop-Pairing.ps1").read_text(encoding="utf-8")
    assert "[Security.SecureString]$BundlePassphrase" in source
    assert re.search(r"if\s*\(\$NonInteractive\s+-and\s+\$null\s+-eq\s+\$BundlePassphrase\)", source)
    assert "New-EncryptedBundle -SourceDirectory $dir -OutputPath $out -Passphrase $BundlePassphrase" in source
    assert "finally{Remove-Item $dir" in source
    assert "Convert-SecureStringToBundlePassword" not in source


def test_complete_cluster_forwards_securestring_inside_existing_cleanup_scope():
    source = (ROOT / "windows" / "Complete-Cluster.ps1").read_text(encoding="utf-8")
    assert "[Security.SecureString]$BundlePassphrase" in source
    assert re.search(r"try\s*\{\s*Expand-EncryptedBundle .* -Passphrase \$BundlePassphrase", source)
    assert "Primary invitation metadata is incomplete." in source
    assert "Vault legacy adoption identity does not match the exact local cluster/credential binding." in source
    assert "finally {\n Remove-Item $dest" in source
    assert "Convert-SecureStringToBundlePassword" not in source


def test_authenticated_bundle_format_and_rejection_guards_are_unchanged():
    create = bundle_function("New-EncryptedBundle")
    expand = bundle_function("Expand-EncryptedBundle")
    assert "$iterations = 600000" in create and "DFENV001" in create
    assert "$aes.Encrypt($nonce, $plain, $cipher, $tag, $header)" in create
    for message in (
        "Encrypted bundle is truncated.",
        "Unsupported encrypted bundle format.",
        "Encrypted bundle KDF parameters are invalid.",
        "Encrypted bundle ciphertext length is invalid.",
    ):
        assert message in expand
    assert "$aes.Decrypt($nonce,$cipher,$tag,$plain,$header)" in expand
    assert expand.index("$aes.Decrypt(") < expand.index("ExtractToDirectory")
    assert "Remove-Item $zipPath -Force -ErrorAction SilentlyContinue" in create
    assert "Remove-Item $zipPath -Force -ErrorAction SilentlyContinue" in expand
