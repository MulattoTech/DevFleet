# Tailscale setup

Normal unattended pairing uses the protected DevFleet OAuth client-secret store. The
pairing code creates a short-lived ACL-protected `file:` input, invokes the installed
Tailscale client once, and removes the file in a `finally` path. The client secret is
never placed in argv, logs, evidence, audit bundles, or installer output.

The one-time local setup command is:

```powershell
& '<repository>\source\windows\Set-DevFleetTailscaleOAuthCredential.ps1'
```

Run it in a local Administrator PowerShell. It uses the existing DevFleet protected
store and a secure prompt; do not paste the secret into Codex, chat, a script file, or
the command line.

Persistent nodes use `tag:devfleet`, deterministic hostnames, and non-ephemeral
registration. Disposable E2E nodes use `tag:devfleet-e2e`, deterministic
collision-safe hostnames, preauthorization where supported, and ephemeral
registration. A healthy authenticated node is validated without reauthentication.

Readiness is layered: the service must run; machine-readable state must show a
Running/authenticated/online node with an expected identity, tag, Tailscale IPv4, and
no blocking health error; the expected peer must answer the supported Tailscale ping;
and the scenario's configured DevFleet endpoint must answer over the tailnet.

`--defer-network-pairing` carries `DeferNetworkPairing` through both PowerShell
entrypoints and leaves a deliberate Maintenance completion path. Browser pairing is
manual recovery only. If Tailnet Lock is enabled or cannot be read safely, automatic
enrollment stops with `TAILNET_LOCK_SIGNING_REQUIRED`; it is never bypassed.
