# Read-only Certification Command Center

This local observer displays native evidence without participating in certification. It reads existing files and Git state; it never refreshes authority, samples HostSafety, reserves charges, starts VMs, or changes release state. Every response sets `certificationCredit=false` and `releaseEligibleClaim=false`. Native release authority remains the only promotion oracle.

Open the **public** checkout in VS Code and run **DevFleet: read-only Certification Command Center** from the task picker. Enter the native checkout's absolute path and the selected successor ledger path relative to that checkout. The task prints a loopback URL, normally `http://127.0.0.1:8768/`. Stop the task to close the server. The server accepts GET requests for `/` and `/snapshot.json` only.

The same view can be launched from a terminal:

```powershell
python tools/certification_command_center.py --native-root 'C:\path\to\native' --ledger 'audit/agent-memory/attempts/<selected-policy>/ledger.json' --public-root . --serve
```

Use `--once` instead of `--serve` to print one JSON snapshot. `--max-age-minutes` changes only the observer's freshness display, never native admission or HostSafety thresholds. The observer reads the newest recorded `*-host-safety.json` file in the selected ledger's `results` directory. A sample without an embedded `observedUtc` is **UNKNOWN** even when its file modification time is available. The observer does not take a new HostSafety sample.

`CURRENT`, `STALE`, `UNKNOWN`, and `CONFLICT` describe the **observer's source consistency**, not release eligibility. Native authority and its tuple must agree with status, gates, FullRelease summary, and proof records. Missing inputs remain UNKNOWN; old timestamps remain STALE; identity or timestamp disagreements become CONFLICT. A recorded L1/L2 cleanup observation includes its own timestamp and `liveState=UNVERIFIED`; it is not a fresh lab inventory. The Developer receipt and first technical failure are tied to the selected ledger's RunIds. Native and public Git histories appear separately.

Root, model, and helper assignments remain UNKNOWN unless an existing native-root-relative JSON snapshot is supplied through `--operator-snapshot`. Its expected fields are `observedUtc`, `root`, `model`, and `helpers`. This optional field is contextual and never changes release credit. Do not put credentials or private evidence in the public checkout.

The public GitHub README is a dated publication snapshot. Use this local view for live read-only observation; use the installed native acceptance contract to determine actual internal eligibility.
