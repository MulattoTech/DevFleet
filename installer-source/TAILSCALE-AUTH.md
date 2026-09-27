# Tailscale authentication

Installation and authentication are separate. The normal automated provider is the
DPAPI-bound `OAuthClientSecretStore` in the existing DevFleet E2E/local secret store.
When authentication is genuinely needed, DevFleet passes the secret through a
tightly ACL-protected temporary file using the installed client's supported
`--client-secret=file:<path>` form. Disposable enrollment adds
`ephemeral=true&preauthorized=true`; persistent enrollment uses
`ephemeral=false&preauthorized=true`, `tag:devfleet`, and unattended Windows
semantics when supported. The secret file is wiped and removed immediately after the
single bounded enrollment call.

The recovery state machine is intentionally small:

1. A healthy service and authenticated node are validated and left unchanged.
2. A stopped service is started once and rechecked.
3. `NeedsLogin`/`NoState` invokes the configured provider once and rechecks structured
   readiness.
4. Other states fail with a specific sanitized classification.

Authentication is not readiness. The final gate also requires a Running backend,
online self, expected deterministic hostname and tag, a Tailscale IPv4, no blocking
health error, the expected peer reachable through the supported Tailscale ping, and
the configured DevFleet service endpoint reachable over the tailnet. These checks are
evidenced as structured metadata without credentials.

If the OAuth provider is unavailable, a protected tagged/preauthorized short-lived
auth-key can be selected explicitly as `AUTH_KEY_FALLBACK`. It follows the same
file-backed, bounded, redacted, and cleanup rules. Browser/device login is emergency
manual recovery only; it is not the normal release path.

Tailnet Lock is read-only inspected before enrollment. Enabled or indeterminate Lock
state fails closed as `TAILNET_LOCK_SIGNING_REQUIRED`; DevFleet never disables or
bypasses Tailnet Lock.

For local secure entry, run the repository-supported script in a local Administrator
PowerShell:

```powershell
& '<repository>\source\windows\Set-DevFleetTailscaleOAuthCredential.ps1'
```

Never pass an OAuth secret, auth key, bearer token, or API token as a command-line
argument or paste one into Codex/chat.
