# DevFleet source part 065

Full-source UTF-8 byte interval [2976000, 3022500); read in order. This is a contiguous text slice, so a code fence/file may continue across parts.
Payload SHA-256: 951c725c3c7b9f6e727d009d06e3f4c4f632dc920f0d2082b128f4a58f6ec10a

<!-- BEGIN SOURCE SLICE -->
ts/Test-MultipassLaunchTimeoutEnvelope.ps1
919655da1d747a27c7e965502ade0de80ac42feeb9592df7b84effa7b79c2ae0  tests/Test-MultipassStandardInputTransport.ps1
0dae89d672d2e5250c009b50f69f4b248e9315bd169cbb82a8828f72d7fff966  tests/Test-PendingReboot.ps1
a553a80e8fbe8c2863faeacf3ccccf4261e7b7e636e819443a1f7410b44bbf1c  tests/Test-ProcessOutputDrain.ps1
4cae989aa96639e30e27d4a444b2bf1ae1c6f922d1cb5203f522b5db7e52408e  tests/Test-TailscaleBrowserPairing.ps1
3767e97aab7be361db254c680245813726b437c4baf2017511d4dbcffbec5dab  tests/Test-TailscaleGuestOAuthTransport.ps1
31de50a4f3beea14044a09fcf7ae763d4b495226d6ebd40d916b1d3be12bf2a2  tests/Test-TailscalePostEnrollmentStatusRetry.ps1
32076c12d01e5c0b9cbc72fb7824959e633e60aa098cadc71f76d8e41182fd23  tests/Test-TailscaleStageDeadlineComposition.ps1
b1ed85f8d67c5ab506ad550fac4d6a93af97ca8a2b9b6ab2ff530ad83aa14846  tests/Test-WindowsIntegrationOwnership.ps1
bcd842e85f5b6c5f4a5365ffbdf032b9b1781b4e9a1a9f811e12652d171727c3  tests/_bundle_layout.py
03e3e1fab21c2523e89b74fb326aca7d38c1927a1aec528997f30558f714ee64  tests/conftest.py
359450217b36e714dd5411b47230100fc0723991377d4ecab213d3ef11ed2a00  tests/test_analyzer.py
11738fb7c631b7c0d2de4d70956ce3e458f5b0aed5d302702ff7bb60ee484ccb  tests/test_analyzer_v11.py
3ce81d650d6d41c7d18b76194d7eefe01feeb1231d80f772051ef845003f0ec1  tests/test_audit5_destructive.py
58d8a589d22f1d4ff33419dbee2864b9a56fe5a9b4a6ffcf4fdc6d1079156e57  tests/test_audit_coherence.py
5b678aec7d5e3adc3205a598f950a73b3102166c0495c9e52bb8076bb031bcaa  tests/test_auth_multiprocess.py
3f7fa30cf012e8451beba327ca3fb255a4b30152c72d30aeb15ea844587b3ba7  tests/test_backup_exit_status.py
eff0c7cc0f43496e74c46f1be348b76a8bedd536389e5f30b6d2521069964e78  tests/test_backup_metadata_acl.py
6416e46165662fcc0e31c37f78c79e89d89991b71fbe6dd8c53786d84dda7be2  tests/test_bootstrap_input_safety.py
493a64b3ce136bc267434b59f1afd5a134efec124cba7b736950b61bc56002f0  tests/test_client_generation.py
3c6790200f5f72039ea577a5398e1824a827686d394a6ef55882e05e789ad118  tests/test_codexpro_hook.py
8fe09b0249911ea8b01eca683e82f01fe488eaa0b01084e404c1962705fde75c  tests/test_configuration.py
d5a00280ded660b836947e6921aa804fcfca33b524853a57a3473848fac185fb  tests/test_csharp_host_agent_response_auth.py
ddf6ab6efb8d2ada422be5e1cb2fc897fe02d619baceec195d823e3d0045dbc0  tests/test_dashboard_v11.py
4cdaf6f35cb09709b2df65afa97dbf56fccb76f517065254ad6d2b99c4eada2b  tests/test_dependency_advisories.py
79fa7f5ef8d85982f8650ed0d58b6716fd0e5327199a7c42f3f002b2e2d2e79d  tests/test_destructive_ownership.py
c64fb764b78450c811014b85c76fcfda076ef98cf3e22003b5767c7131109bd8  tests/test_destructive_safety_transaction.py
5340bdf18fc9026bfca919acc59f908d4065dcfc756d1f5fe156d3b5cad85759  tests/test_docker_modes.py
3a7ca4b6a92618c2f753dad9d0e86b72253b9550bd61379fbd2301c1edd986bd  tests/test_existing_runtime_assignment.py
b69044da502f5c37cc4cd12d91091606a314ba90f0ff1157002439abb7ca5e6c  tests/test_failover.py
c0639e0edc66abb29fdac71605866a0f1a488de357df153d743f825a2898546e  tests/test_hardening11_red_blue.py
c76ba7108747796dc74b7ff6c4d026d5be2672dd2b4e99d14fc6f0f49bcbd8bb  tests/test_hardening7_boundaries.py
6af8731cc3e3d84adf2d355de336e1adf60780f5072dee5ac7b998124532ec29  tests/test_hardening8_api_serialization.py
a69ff2930191b209eff2bc8d772d2bcc824fa314f8fb54b464b4b7de975a9af2  tests/test_hardening8_container_ownership.py
1573d8d8d6573200b2e6be1d2ae0532d37d5dfdc14fc28e830a4f3c9d1a744d8  tests/test_hardening8_manifest_version.py
91a4d0d581078bc37003de7e0002f40151be9b141155fd587b8dfd7991720917  tests/test_hardening8_restore_journal.py
6eee62b71d85f1f9971a38c129cc7fe010f4499084ef6ca02dd87e4b4e70d4e5  tests/test_hardening8_secret_recovery.py
785ff9fe6ec7a77292fe410d5a25dc9eb500c1c19288f35449fd4118d3986fdc  tests/test_hardening8_systemd_contract.py
4d7f62f7b1950263e5a069faca8fdedb2fec42afc45e7125c13f49dc1e0fb522  tests/test_hardening8_windows_integrations.py
9d3a2b7a6fb5c0172eff50e8b184e7a1c03cc55f084841d71652ef9d9f02e5b3  tests/test_hardening9_filesystem_identity.py
bb42499c40a9c1fb9567090f96312700047ce6c5208440df86557d349137205a  tests/test_host_agent_idle_polling.py
83eba1dc0ef71d3db5def5f1dd72969b96dbd6c763819fedb60e9432ac4eb9af  tests/test_host_agent_integration.py
bed644c01d6b81ece6eaf76db5199df20b9e1892c026b7b6fee0e98b2f8c6a7f  tests/test_host_safe_architecture.py
1afeb36061b7f8dc92233be15f77b8f6269d00177aa0511665c1d6132b0d0f36  tests/test_host_transport.py
a096005c7bb6023e7242ea56517338137f4e8a516ab901bd37786afeffee1bf5  tests/test_installed_dependency_authenticity.py
966731a830d6a62ca9fa6d366ae88252a4c8d60f28fbe645221e35dc6a10ce25  tests/test_installer_self_cleanup.py
bf6448bdd5f7ee48208912fee44e08c99614c72f7ec036c9e4301a91d6cc60d7  tests/test_language_templates.py
a255b83381a5753c49b6029fdd6308ba0ac14d6a2a3774d0aa0dd2eaef0bcd3a  tests/test_laptop_profile.py
499afe9442a2d9944d4fe7fc1c363c3f28880c8702472d5c9d45c610aa1c509b  tests/test_laptop_tailscale_bootstrap.py
f1bdba4aa4c2d6501bd193ed8d1a4f1ac9d3ea1988d57df5e7f55a0e69f626f9  tests/test_metadata_io.py
1d6a93dd189f54371d54ac9b3639a415b9b29995c95e1a3f2ae422f8a1fc12b7  tests/test_migration_integration.py
ae80d2cdaa7f48f283367ab50a4f96c4939a540f098929bee2d69bd0cc4ff836  tests/test_network_policy.py
20b6f1d35bec5b55649482f1fdd28fba68f2a2a5a7a33b6cc4a68aabfd3f695f  tests/test_node_registry.py
ca9a7739053062da4e2085d89055277aacce1b1763debf0efacc5926c01f531b  tests/test_ollama.py
e4d54f47f0354e6f314c5f7c0515249aba022b743192ba8e82ba0e378542a8d0  tests/test_operations_leases.py
e1b5312e7c28c0c54ccdf1a7d4b23c700f65bb15c436ccf0f0ef82258fcf17a0  tests/test_package_structure.py
69352da5f3ec0cfdf73a8a6deff2c6afc7a3068a01cdb1bd1aff0b8327e73af0  tests/test_packaging_hygiene.py
f7fda6b02b77ac84c8ad43838a34c13b75820b7130daa55411d7c2816cd24306  tests/test_pairing_passphrase_contract.py
6462892dce04a296322461f1046aa5e87ed72923caff2fad024f04cbdb42fff2  tests/test_posix_zip_writer.py
c2b6c38df7c926f5b7e7151be4f2089786a023849ffd9a0a5d5cc0de2e42156c  tests/test_profiles.py
eaa01b1294d8f5a0e4b4b4debc59a7cf540305716a90b71dbdfeb9e08fa41187  tests/test_project_safety.py
c828417c604b08df30002a8af2a26a1070fbdf112b1e7e80dfd8635c883c6dd3  tests/test_release_fingerprint.py
f4af5c9897f923c4579ad5b5ede734d64067968ff58622b1bd25be24dccef66c  tests/test_release_reproducibility.py
de0445f35b1c084cd557e7edede914adf0282aa5931dc47fc6dcf86fc00bcdad  tests/test_remediation_contract.py
084475db61c654d14637f96eaec248355c9f4c7d1c7e9c160835f622d62a66fc  tests/test_request_admission.py
7fb003753a830ba6f20ece02678ff9a96016cc5b35b6a4a84e04a275d7145b1c  tests/test_runtime_architecture.py
fb7ee1c2c975d37447ddb4ef91ccb7673adfe7a84f7ba446f7ee6db9c39d2a2a  tests/test_safety_backup_lease_drift.py
e372fd0f3ddc6f2c90c244295828ad648abbcca689465ca29f7125d8e86ef6d5  tests/test_security_config.py
3b38b5f668c5cf6e9868778a365f16a7b105f95b38e861a1165d8797d3e32744  tests/test_security_poison_harness.py
e1284a9228410bb613bd8f942caf99d554e69d34d90f5e85e06a38f156531590  tests/test_transitive_hook_closure.py
bc0b93eb5559346b2781139dbcaf21b98e1d7628e677630402f78b40e1e67763  tests/test_upgrade_preservation.py
b338d6aafbeededad000f91c837375a3886c8461daf71e9f59b52ec2be8d4514  tests/test_v1211_release_contract.py
1ceffa011ec0d19a052a4d3551879ee1dfd089d9ee07f21be3b05cd7cb40ab84  tests/test_v1211_stopped_capabilities.py
a88a21055e555d85b2ebfa0ba63a18372c49dbb16a2f0c517efd71b3485fff98  tests/test_v121_auth_performance.py
e8537161bda817b8cd7539ce4c40a078b8cef1d0a88477c3e8cf33910056f285  tests/test_v122_auth_snapshot_package.py
acd775b9253d3b6cf0a22d984731107e49253d632b05d000a28129d41875eb30  tests/test_v122_lifecycle_archive.py
2c5ca92e1e82ad5b08d479de308347045410861c60df9abafd86dc7f3303e420  tests/test_v122_main_endpoints.py
2d3f276abc1105aa61a069eb5669c3775a0bf472929779b9722834f1ad0f366a  tests/test_v122_ui.py
0012c02123620453c6a2731dced0ea6ea1aa72603fa31fe79c9afb4ffd7f411c  tests/test_v123_contracts.py
b2b93383246e28effa2efc2c2313b2406adf7603ca57fee9926a3090119a4263  tests/test_v123_durable_operations.py
6f4d0f458c1569459e509821d2d0e7ea3927b7dd4361caa13e627e921761cc24  tests/test_v123_vault_broker.py
d13055a62902cdfe9b0ff6ab24dc8e0e3dab1e3fd79b0a21cda26cc01ee84633  tests/test_v123_vault_restore_transaction.py
cc35cdd574c4a2e12f84169d3b821030eead1bced0d3f1edcc3d09da6d478e0e  tests/test_v124_environment_wizard.py
74c240589060a7fe59d71b6a829689c2564bcaa3a5cba00039060d05546b2ae9  tests/test_v124_migration_transaction.py
635be7cf6db6bcc88cbae397e782da8c586aef63d6824ad0f3bc6bcf2959fb48  tests/test_v124_vm_backups.py
705b439b834162d0890b8b4b4bb42ed66dc300e76b409de537520323dd8ebe6c  tests/test_v124_vm_creation_ssh.py
f8f3e5ce386a3ce3b8c85a0514a09bbb702e935f716e4cd5e8b3c98e44f3b0da  tests/test_v125_jobfinder_hotfix.py
3c793e1ea5beffe6b9bc87abd2de1f9ebd06abe38cb6b496fb66237e0551afe2  tests/test_v126_dynamic_vm_hotfix.py
20e0a996802df6a6af676e448ea497d6d032063de574581f705071330c2e2a62  tests/test_v127_project_ux.py
f947532feee6305c049ffa245545e60dc389ae6507b44552914471ebabbf4ae9  tests/test_v128_container_workspace.py
f5340252c6b2410b726c4529c51ecef9ec9aab60b41c5ca3cef989573668b9d3  tests/test_vault_metadata_identity_integration.py
51cb998ef256cd58f3c6f63c63d23aa330566f0f4030c7f7237eb962967c3d4c  tests/test_verify_package_watchdog.py
7cf54e4291b6c4df1063afb2ab5113bf35b78498c8f035ac1633d3c41d7c3b2f  tests/test_worktrees_and_v1_restore.py
8b654e01e2be6f4faa42628be4168e9c349348a8dac29fa8cbf5d24bf86badcf  tools/Build-InstallerSourceZip.ps1
823ed5d1f17bf4b46a0f8f306ff73833df46ab50221734ff5116a8cac7e84cec  tools/Verify-Package.ps1
59e38747a1c410ea7710b522c5bb2dab73adb841e892503c87114aed97dc5712  tools/build_release.py
8901ed5ad3d19846030f2c6b8af5f03274277ef76b641b540a127d9994906185  tools/check_dependency_advisories.py
3010bf588f088c9e6d4e956c2127a06abfec78f4875eec3441475383b6e02e54  tools/hook_modes.py
38e5b6be41be5d9a22039b047a5489ab476dce3ea02d9217e3737d3f07e4bdaa  tools/migrate_config.py
f5440bfaeafb54607fa71d284ec6d63e115fe15e2de6e72bc7f1de644363cf6b  tools/release_fingerprint.py
d9f46d511192d552013ce289ffe7547bb3befd1d9c65d40b61038e979e93a70c  tools/validate_ai_audit_bundle.py
9c5f6b489571f076a332da9128767ccc44d72882445b72029e5f2c07cafed651  tools/validate_audit_coherence.py
24d74c58ed2d13099032cbc4a2ef46a03c819da82b7505762ff2068ed8a1ea9b  tools/verify_package.py
10088dbe4b07289b6f3df8811a75a2c58a2ad65b0b44f728f448c7cbc2129cda  tools/write_posix_zip.py
e9a3edb41802e9a01d76641f133430d683c84d37cf43604a492ebf106827c731  windows/00-Preflight.ps1
bc4d60449c0633509984438a3a41a8d5077222e66ca57e79f20f621fe076f81b  windows/01-Install-Prerequisites.ps1
e06b31924cb383c9d6383c70376b89b49213248f1f09e61aef5dc15d8afff7d1  windows/02-Provision-ComputeNode.ps1
620c99ab23861ad44f74b5d79ceda9e79eba20feb89ff6694e0e548e2a5308c6  windows/03-Provision-Vault.ps1
a8c18e358eeeeb4c00058fc893f165c2d47f90015e06abde8265bd7ae98b077b  windows/04-Connect-Tailscale.ps1
361255d8773a9de440bac3007db55635a7940e49409d77f9245651df44c3585b  windows/04a-Connect-WindowsTailscale.ps1
9687c9be4a3bf40a2e1481cd402c7d4118aaa0c4533e9037244b7bb3a25e0c62  windows/05-Configure-LocalVaultClient.ps1
e38b19b780ca0a6ef94aba9a71a225d4a6cc28d5c3fe6c80333f7fa0d00c8452  windows/06-Import-Laptop-Bootstrap.ps1
e8295df36470ee12ca2ea696195bbee0e64333ddce1c45f80aae3a2f37844a5f  windows/08-Install-Shortcuts.ps1
806d2edbce838681979ac40678aeb452e2f6e0be87b2baafc307adb3813073c4  windows/09-Export-Laptop-Bootstrap.ps1
a20531c8ca0e0e2a85a720a0089b97fc769410b2246a93443014074e17ea45ee  windows/10-Export-Desktop-Pairing.ps1
0168e428da1749b5ece2d61eb2df324fab835424e3d1de4af9576aea6e4baf74  windows/Complete-Cluster.ps1
0c386e55d8d961d12708551ea4e30b0b2c224c1d25fd48f6a1c84f16bafa6432  windows/Configure-DevFleet-HostControl.ps1
39ad88bc44596bfcb497d0b69f92130d859e338b878b6ad27d8fa1376f62e9d4  windows/Configure-GitHub.ps1
fffd6eb381da44ab8239be426bccf4260b196b4d48cdb9606289df62d2b322bd  windows/Configure-Ollama.ps1
bf68455620a50dab6d3d470f54b264899d4712f553632c5180d7dc420e130bf2  windows/DevFleet-HostAgent.ps1
6e1b0bcea1194b7a4b5443f80b8af01e8331ed6772578cac272867de3334034f  windows/DevFleet-HostAgentProtocol.psm1
6e7ab0758d482f69112085ce84d153b9d5a7ab645d70da1a92963d24e38f7248  windows/DevFleet-VSCode.ps1
a05f3e85b4033d59e61d4ccdaa06bc8051befb711ae2b6fb26880f1ae89f1b0e  windows/DevFleet-WindowsIntegrationOwnership.psm1
29e4a7fae0fde808e7e295bf4c9371be7da0cd2a37979d4347f3fb207f0c59d7  windows/DevFleet.Common.psm1
b64b38830684a097fa8e1e60440f37894ce4b25e765016172ffb6a899bcf6afd  windows/DevFleet.Tailscale.psm1
fd1dbee84b4be48f94162c14e75ed847f6c15a6ed898c08e86ddb0a827437cf3  windows/Export-Diagnostics.ps1
2ec63a9fa38753b0f55ff752faa9f3511b47e2fca70cff9b432fac2823eb9dd7  windows/Export-Vault-OfflineCopy.ps1
2f8aaeef509e22b14ee2f53b7cc64ef92851042e7487c0e5eefacd9c77c7396b  windows/Install-DevFleet-HostAgent.ps1
6770649aab6111d099e0ef4652238910cbfc61a69b4815686fadf052068e6eb8  windows/Invoke-Quarantine-Maintenance.ps1
ebf2557670dfd98191f8918699b08ef6607f166429943034fb96f2d4473944dd  windows/Invoke-Vault-Maintenance.ps1
05506c1475b1562de935be365873970bb297f6f5adff8d281d7b82db9e20ec7f  windows/Migrate-Config.ps1
a3fa2f7e42741649e8c5098b24574a4d2dd49b0c6f1815f5df25e096e64e1d80  windows/Remove-DevFleet-OwnedIntegrations.ps1
a0c494824681657502694ef8cdd9622a247a9401d549fefb17fdbf37632e9ad5  windows/Repair-DevFleet.ps1
6c3233e1643fa8a5e317ee04a98da27b40c297ad15f961a68c5d5ccfd0ceba4b  windows/Repair-DevFleetHostSecrets.ps1
f76be7c8d6fc8364fba6b7a142efe687351355681473e56cc30b51e021377f95  windows/Set-DevFleetDockerMode.ps1
0105c2847c27380d28d1dc28f2866309f107ced8dd750589b42185bd39bc27f3  windows/Set-DevFleetTailscaleOAuthCredential.ps1
71a2690913ce61e9a48b24bcf7bcf6a6933c41b46b432375a212ebc3a2b159aa  windows/Show-DevFleet-Credentials.ps1
111e3e8828b164feae5ec9bc7a0000683bbb8bbb77c4921aab5b28713447f404  windows/Start-DevFleet.ps1
e74baad7cd8e7ba9f706710b17bcae7e736266d8dc41d6f326243609a140a8e5  windows/Stop-DevFleet.ps1
900e430ea23f0f2980da8d9529389a5abc06c4fefc3e2195ba6e76f3bb70f245  windows/Test-DevFleet.ps1
d64c2328cb6057dc0bccf78051fdb523da928df89ed9b6ae713f961dab30aaf1  windows/Test-Ollama.ps1
6eb437cd4cf6a5d29fcd25c202d50d9a7ed738e2c76d9c5763d2acc64d13ff23  windows/Update-DevFleet.ps1
bbd371182a3002edfe1e3b8995ad1a437d706eac8ed4b9713a4f7252339d7069  windows/Update-Vault.ps1
1e1a37ba016238f122173ce7bd22c0909ce2b155d47c23f6430fd15440020705  windows/Verify-DevFleet-Host.ps1

```


## FILE: source/DevFleet-v1.1.0-FILE-CHANGES.md

SHA256: 1bf9481ca5be5676e0070de024f05e66fa60a6e817c1999b71d3194ac79af892 | Bytes: 29390 | Git mode: 100644

```
# DevFleet v1.2.1 file-change audit

This report compares the final v1.2.1 package tree with the verified v1.0.0 archive whose SHA-256 is
`ac9a56b032766728fc51d92972c6c083f181b8fb90576f1679fb1a2407c76345`.

## Summary

- v1.0.0 baseline files: **95**
- Final v1.1.0 package files: **583**
- Files added in v1.1.0: **488**
- Existing files modified: **55**
- Existing files removed: **0**
- Existing files unchanged: **40**

No v1.0.0 file path was removed. The original v1.0.0 ZIP remains a separate artifact.

## Major additive areas

- Schema-2 configuration migration and idempotent upgrade entry point.
- Development profiles, Docker-store selection, shared caches, analyzer cache, and ownership leases.
- CodexPro adapter/status/session prompts without embedded credentials or invented private controls.
- Language-aware project generation with 10 core and 10 preview templates.
- Remote SSH, Docker context, VS Code, Windows Ollama, progress operations, and expanded tests/docs.

## Added files

- `BASELINE-v1.0.0-FILES.txt`
- `DevFleet-v1.1.0-FILE-CHANGES.md`
- `DevFleet-v1.1.0-MIGRATION.md`
- `DevFleet-v1.1.0-VALIDATION.md`
- `Upgrade-DevFleet.ps1`
- `VERSION`
- `app/devfleet/caches.py`
- `app/devfleet/codexpro.py`
- `app/devfleet/configuration.py`
- `app/devfleet/failover.py`
- `app/devfleet/language_policy.py`
- `app/devfleet/leases.py`
- `app/devfleet/ollama.py`
- `app/devfleet/operations.py`
- `app/devfleet/profiles.py`
- `client/Configure-DockerContext.ps1`
- `client/Configure-SSH.ps1`
- `client/Configure-VSCode.ps1`
- `client/ssh-config.example`
- `client/vscode-extensions-core.txt`
- `client/vscode-extensions-enterprise.txt`
- `client/vscode-extensions-python.txt`
- `client/vscode-extensions-systems.txt`
- `client/vscode-extensions-web.txt`
- `client/vscode-settings.jsonc`
- `config/ollama-profiles.json`
- `docs/08-DEVELOPMENT-PROFILES.md`
- `docs/09-LANGUAGE-SELECTION.md`
- `docs/10-OLLAMA-AND-GPU.md`
- `docs/11-REMOTE-VSCODE.md`
- `docs/12-UPGRADING-FROM-1.0.0.md`
- `docs/13-PERFORMANCE-TUNING.md`
- `linux/devfleet-docker-mode-report`
- `linux/devfleet-switch-docker-mode`
- `linux/upgrade-compute.sh`
- `pytest.ini`
- `templates/cpp-cmake/.ai-bridge/chatgpt-memory.md`
- `templates/cpp-cmake/.ai-bridge/codexpro-project-instructions.md`
- `templates/cpp-cmake/.ai-bridge/current-plan.template.md`
- `templates/cpp-cmake/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/cpp-cmake/.ai-bridge/prompts/handoff-template.md`
- `templates/cpp-cmake/.ai-bridge/prompts/reconnect.md`
- `templates/cpp-cmake/.ai-bridge/prompts/session-bootstrap.md`
- `templates/cpp-cmake/.devcontainer/devcontainer.json`
- `templates/cpp-cmake/.devfleet/bootstrap.sh`
- `templates/cpp-cmake/.devfleet/codexpro-bootstrap.sh`
- `templates/cpp-cmake/.devfleet/codexpro-profile.json`
- `templates/cpp-cmake/.devfleet/codexpro.env.example`
- `templates/cpp-cmake/.devfleet/health-check.sh`
- `templates/cpp-cmake/.devfleet/project-tools.json`
- `templates/cpp-cmake/.devfleet/smoke-test.sh`
- `templates/cpp-cmake/.devfleet/template.json`
- `templates/cpp-cmake/.editorconfig`
- `templates/cpp-cmake/.gitignore`
- `templates/cpp-cmake/README.md`
- `templates/cpp-cmake/compose.yaml`
- `templates/cpp-cmake/docs/architecture.md`
- `templates/data-r/.ai-bridge/chatgpt-memory.md`
- `templates/data-r/.ai-bridge/codexpro-project-instructions.md`
- `templates/data-r/.ai-bridge/current-plan.template.md`
- `templates/data-r/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/data-r/.ai-bridge/prompts/handoff-template.md`
- `templates/data-r/.ai-bridge/prompts/reconnect.md`
- `templates/data-r/.ai-bridge/prompts/session-bootstrap.md`
- `templates/data-r/.devcontainer/devcontainer.json`
- `templates/data-r/.devfleet/bootstrap.sh`
- `templates/data-r/.devfleet/codexpro-bootstrap.sh`
- `templates/data-r/.devfleet/codexpro-profile.json`
- `templates/data-r/.devfleet/codexpro.env.example`
- `templates/data-r/.devfleet/health-check.sh`
- `templates/data-r/.devfleet/project-tools.json`
- `templates/data-r/.devfleet/smoke-test.sh`
- `templates/data-r/.devfleet/template.json`
- `templates/data-r/.editorconfig`
- `templates/data-r/.gitignore`
- `templates/data-r/README.md`
- `templates/data-r/compose.yaml`
- `templates/data-r/docs/architecture.md`
- `templates/dotnet-service/.ai-bridge/chatgpt-memory.md`
- `templates/dotnet-service/.ai-bridge/codexpro-project-instructions.md`
- `templates/dotnet-service/.ai-bridge/current-plan.template.md`
- `templates/dotnet-service/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/dotnet-service/.ai-bridge/prompts/handoff-template.md`
- `templates/dotnet-service/.ai-bridge/prompts/reconnect.md`
- `templates/dotnet-service/.ai-bridge/prompts/session-bootstrap.md`
- `templates/dotnet-service/.devcontainer/devcontainer.json`
- `templates/dotnet-service/.devfleet/bootstrap.sh`
- `templates/dotnet-service/.devfleet/codexpro-bootstrap.sh`
- `templates/dotnet-service/.devfleet/codexpro-profile.json`
- `templates/dotnet-service/.devfleet/codexpro.env.example`
- `templates/dotnet-service/.devfleet/health-check.sh`
- `templates/dotnet-service/.devfleet/project-tools.json`
- `templates/dotnet-service/.devfleet/smoke-test.sh`
- `templates/dotnet-service/.devfleet/template.json`
- `templates/dotnet-service/.editorconfig`
- `templates/dotnet-service/.gitignore`
- `templates/dotnet-service/README.md`
- `templates/dotnet-service/compose.yaml`
- `templates/dotnet-service/docs/architecture.md`
- `templates/dotnet-service/src/App/App.csproj`
- `templates/dotnet-service/src/App/Program.cs`
- `templates/dotnet-service/tests/Smoke/Smoke.csproj`
- `templates/dotnet-service/tests/Smoke/SmokeTest.cs`
- `templates/elixir-phoenix/.ai-bridge/chatgpt-memory.md`
- `templates/elixir-phoenix/.ai-bridge/codexpro-project-instructions.md`
- `templates/elixir-phoenix/.ai-bridge/current-plan.template.md`
- `templates/elixir-phoenix/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/elixir-phoenix/.ai-bridge/prompts/handoff-template.md`
- `templates/elixir-phoenix/.ai-bridge/prompts/reconnect.md`
- `templates/elixir-phoenix/.ai-bridge/prompts/session-bootstrap.md`
- `templates/elixir-phoenix/.devcontainer/devcontainer.json`
- `templates/elixir-phoenix/.devfleet/bootstrap.sh`
- `templates/elixir-phoenix/.devfleet/codexpro-bootstrap.sh`
- `templates/elixir-phoenix/.devfleet/codexpro-profile.json`
- `templates/elixir-phoenix/.devfleet/codexpro.env.example`
- `templates/elixir-phoenix/.devfleet/health-check.sh`
- `templates/elixir-phoenix/.devfleet/project-tools.json`
- `templates/elixir-phoenix/.devfleet/smoke-test.sh`
- `templates/elixir-phoenix/.devfleet/template.json`
- `templates/elixir-phoenix/.editorconfig`
- `templates/elixir-phoenix/.gitignore`
- `templates/elixir-phoenix/README.md`
- `templates/elixir-phoenix/compose.yaml`
- `templates/elixir-phoenix/docs/architecture.md`
- `templates/flutter/.ai-bridge/chatgpt-memory.md`
- `templates/flutter/.ai-bridge/codexpro-project-instructions.md`
- `templates/flutter/.ai-bridge/current-plan.template.md`
- `templates/flutter/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/flutter/.ai-bridge/prompts/handoff-template.md`
- `templates/flutter/.ai-bridge/prompts/reconnect.md`
- `templates/flutter/.ai-bridge/prompts/session-bootstrap.md`
- `templates/flutter/.devcontainer/devcontainer.json`
- `templates/flutter/.devfleet/bootstrap.sh`
- `templates/flutter/.devfleet/codexpro-bootstrap.sh`
- `templates/flutter/.devfleet/codexpro-profile.json`
- `templates/flutter/.devfleet/codexpro.env.example`
- `templates/flutter/.devfleet/health-check.sh`
- `templates/flutter/.devfleet/project-tools.json`
- `templates/flutter/.devfleet/smoke-test.sh`
- `templates/flutter/.devfleet/template.json`
- `templates/flutter/.editorconfig`
- `templates/flutter/.gitignore`
- `templates/flutter/README.md`
- `templates/flutter/compose.yaml`
- `templates/flutter/docs/architecture.md`
- `templates/generic/.ai-bridge/chatgpt-memory.md`
- `templates/generic/.ai-bridge/codexpro-project-instructions.md`
- `templates/generic/.ai-bridge/current-plan.template.md`
- `templates/generic/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/generic/.ai-bridge/prompts/handoff-template.md`
- `templates/generic/.ai-bridge/prompts/reconnect.md`
- `templates/generic/.ai-bridge/prompts/session-bootstrap.md`
- `templates/generic/.devfleet/bootstrap.sh`
- `templates/generic/.devfleet/codexpro-profile.json`
- `templates/generic/.devfleet/health-check.sh`
- `templates/generic/.devfleet/project-tools.json`
- `templates/generic/.devfleet/smoke-test.sh`
- `templates/generic/.devfleet/template.json`
- `templates/generic/.editorconfig`
- `templates/generic/docs/architecture.md`
- `templates/go-service/.ai-bridge/chatgpt-memory.md`
- `templates/go-service/.ai-bridge/codexpro-project-instructions.md`
- `templates/go-service/.ai-bridge/current-plan.template.md`
- `templates/go-service/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/go-service/.ai-bridge/prompts/handoff-template.md`
- `templates/go-service/.ai-bridge/prompts/reconnect.md`
- `templates/go-service/.ai-bridge/prompts/session-bootstrap.md`
- `templates/go-service/.devcontainer/devcontainer.json`
- `templates/go-service/.devfleet/bootstrap.sh`
- `templates/go-service/.devfleet/codexpro-bootstrap.sh`
- `templates/go-service/.devfleet/codexpro-profile.json`
- `templates/go-service/.devfleet/codexpro.env.example`
- `templates/go-service/.devfleet/health-check.sh`
- `templates/go-service/.devfleet/project-tools.json`
- `templates/go-service/.devfleet/smoke-test.sh`
- `templates/go-service/.devfleet/template.json`
- `templates/go-service/.editorconfig`
- `templates/go-service/.gitignore`
- `templates/go-service/README.md`
- `templates/go-service/compose.yaml`
- `templates/go-service/docs/architecture.md`
- `templates/go-service/go.mod`
- `templates/go-service/main.go`
- `templates/go-service/main_test.go`
- `templates/java-spring/.ai-bridge/chatgpt-memory.md`
- `templates/java-spring/.ai-bridge/codexpro-project-instructions.md`
- `templates/java-spring/.ai-bridge/current-plan.template.md`
- `templates/java-spring/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/java-spring/.ai-bridge/prompts/handoff-template.md`
- `templates/java-spring/.ai-bridge/prompts/reconnect.md`
- `templates/java-spring/.ai-bridge/prompts/session-bootstrap.md`
- `templates/java-spring/.devcontainer/devcontainer.json`
- `templates/java-spring/.devfleet/bootstrap.sh`
- `templates/java-spring/.devfleet/codexpro-bootstrap.sh`
- `templates/java-spring/.devfleet/codexpro-profile.json`
- `templates/java-spring/.devfleet/codexpro.env.example`
- `templates/java-spring/.devfleet/health-check.sh`
- `templates/java-spring/.devfleet/project-tools.json`
- `templates/java-spring/.devfleet/smoke-test.sh`
- `templates/java-spring/.devfleet/template.json`
- `templates/java-spring/.editorconfig`
- `templates/java-spring/.gitignore`
- `templates/java-spring/README.md`
- `templates/java-spring/compose.yaml`
- `templates/java-spring/docs/architecture.md`
- `templates/java-spring/pom.xml`
- `templates/java-spring/src/main/java/com/devfleet/Application.java`
- `templates/java-spring/src/test/java/com/devfleet/ApplicationTest.java`
- `templates/kotlin-service/.ai-bridge/chatgpt-memory.md`
- `templates/kotlin-service/.ai-bridge/codexpro-project-instructions.md`
- `templates/kotlin-service/.ai-bridge/current-plan.template.md`
- `templates/kotlin-service/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/kotlin-service/.ai-bridge/prompts/handoff-template.md`
- `templates/kotlin-service/.ai-bridge/prompts/reconnect.md`
- `templates/kotlin-service/.ai-bridge/prompts/session-bootstrap.md`
- `templates/kotlin-service/.devcontainer/devcontainer.json`
- `templates/kotlin-service/.devfleet/bootstrap.sh`
- `templates/kotlin-service/.devfleet/codexpro-bootstrap.sh`
- `templates/kotlin-service/.devfleet/codexpro-profile.json`
- `templates/kotlin-service/.devfleet/codexpro.env.example`
- `templates/kotlin-service/.devfleet/health-check.sh`
- `templates/kotlin-service/.devfleet/project-tools.json`
- `templates/kotlin-service/.devfleet/smoke-test.sh`
- `templates/kotlin-service/.devfleet/template.json`
- `templates/kotlin-service/.editorconfig`
- `templates/kotlin-service/.gitignore`
- `templates/kotlin-service/README.md`
- `templates/kotlin-service/compose.yaml`
- `templates/kotlin-service/docs/architecture.md`
- `templates/node/.ai-bridge/chatgpt-memory.md`
- `templates/node/.ai-bridge/codexpro-project-instructions.md`
- `templates/node/.ai-bridge/current-plan.template.md`
- `templates/node/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/node/.ai-bridge/prompts/handoff-template.md`
- `templates/node/.ai-bridge/prompts/reconnect.md`
- `templates/node/.ai-bridge/prompts/session-bootstrap.md`
- `templates/node/.devfleet/bootstrap.sh`
- `templates/node/.devfleet/codexpro-profile.json`
- `templates/node/.devfleet/health-check.sh`
- `templates/node/.devfleet/project-tools.json`
- `templates/node/.devfleet/smoke-test.sh`
- `templates/node/.devfleet/template.json`
- `templates/node/.editorconfig`
- `templates/node/docs/architecture.md`
- `templates/node/src/index.js`
- `templates/node/test/index.test.js`
- `templates/php-laravel/.ai-bridge/chatgpt-memory.md`
- `templates/php-laravel/.ai-bridge/codexpro-project-instructions.md`
- `templates/php-laravel/.ai-bridge/current-plan.template.md`
- `templates/php-laravel/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/php-laravel/.ai-bridge/prompts/handoff-template.md`
- `templates/php-laravel/.ai-bridge/prompts/reconnect.md`
- `templates/php-laravel/.ai-bridge/prompts/session-bootstrap.md`
- `templates/php-laravel/.devcontainer/devcontainer.json`
- `templates/php-laravel/.devfleet/bootstrap.sh`
- `templates/php-laravel/.devfleet/codexpro-bootstrap.sh`
- `templates/php-laravel/.devfleet/codexpro-profile.json`
- `templates/php-laravel/.devfleet/codexpro.env.example`
- `templates/php-laravel/.devfleet/health-check.sh`
- `templates/php-laravel/.devfleet/project-tools.json`
- `templates/php-laravel/.devfleet/smoke-test.sh`
- `templates/php-laravel/.devfleet/template.json`
- `templates/php-laravel/.editorconfig`
- `templates/php-laravel/.gitignore`
- `templates/php-laravel/README.md`
- `templates/php-laravel/compose.yaml`
- `templates/php-laravel/docs/architecture.md`
- `templates/python-fastapi/.ai-bridge/chatgpt-memory.md`
- `templates/python-fastapi/.ai-bridge/codexpro-project-instructions.md`
- `templates/python-fastapi/.ai-bridge/current-plan.template.md`
- `templates/python-fastapi/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/python-fastapi/.ai-bridge/prompts/handoff-template.md`
- `templates/python-fastapi/.ai-bridge/prompts/reconnect.md`
- `templates/python-fastapi/.ai-bridge/prompts/session-bootstrap.md`
- `templates/python-fastapi/.devcontainer/devcontainer.json`
- `templates/python-fastapi/.devfleet/bootstrap.sh`
- `templates/python-fastapi/.devfleet/codexpro-bootstrap.sh`
- `templates/python-fastapi/.devfleet/codexpro-profile.json`
- `templates/python-fastapi/.devfleet/codexpro.env.example`
- `templates/python-fastapi/.devfleet/health-check.sh`
- `templates/python-fastapi/.devfleet/project-tools.json`
- `templates/python-fastapi/.devfleet/smoke-test.sh`
- `templates/python-fastapi/.devfleet/template.json`
- `templates/python-fastapi/.editorconfig`
- `templates/python-fastapi/.gitignore`
- `templates/python-fastapi/README.md`
- `templates/python-fastapi/compose.yaml`
- `templates/python-fastapi/docs/architecture.md`
- `templates/python-fastapi/pyproject.toml`
- `templates/python-fastapi/src/app/__init__.py`
- `templates/python-fastapi/src/app/main.py`
- `templates/python-fastapi/tests/test_smoke.py`
- `templates/python/.ai-bridge/chatgpt-memory.md`
- `templates/python/.ai-bridge/codexpro-project-instructions.md`
- `templates/python/.ai-bridge/current-plan.template.md`
- `templates/python/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/python/.ai-bridge/prompts/handoff-template.md`
- `templates/python/.ai-bridge/prompts/reconnect.md`
- `templates/python/.ai-bridge/prompts/session-bootstrap.md`
- `templates/python/.devfleet/bootstrap.sh`
- `templates/python/.devfleet/codexpro-profile.json`
- `templates/python/.devfleet/health-check.sh`
- `templates/python/.devfleet/project-tools.json`
- `templates/python/.devfleet/smoke-test.sh`
- `templates/python/.devfleet/template.json`
- `templates/python/.editorconfig`
- `templates/python/docs/architecture.md`
- `templates/python/src/app/main.py`
- `templates/python/tests/test_smoke.py`
- `templates/ruby-rails/.ai-bridge/chatgpt-memory.md`
- `templates/ruby-rails/.ai-bridge/codexpro-project-instructions.md`
- `templates/ruby-rails/.ai-bridge/current-plan.template.md`
- `templates/ruby-rails/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/ruby-rails/.ai-bridge/prompts/handoff-template.md`
- `templates/ruby-rails/.ai-bridge/prompts/reconnect.md`
- `templates/ruby-rails/.ai-bridge/prompts/session-bootstrap.md`
- `templates/ruby-rails/.devcontainer/devcontainer.json`
- `templates/ruby-rails/.devfleet/bootstrap.sh`
- `templates/ruby-rails/.devfleet/codexpro-bootstrap.sh`
- `templates/ruby-rails/.devfleet/codexpro-profile.json`
- `templates/ruby-rails/.devfleet/codexpro.env.example`
- `templates/ruby-rails/.devfleet/health-check.sh`
- `templates/ruby-rails/.devfleet/project-tools.json`
- `templates/ruby-rails/.devfleet/smoke-test.sh`
- `templates/ruby-rails/.devfleet/template.json`
- `templates/ruby-rails/.editorconfig`
- `templates/ruby-rails/.gitignore`
- `templates/ruby-rails/README.md`
- `templates/ruby-rails/compose.yaml`
- `templates/ruby-rails/docs/architecture.md`
- `templates/rust-service/.ai-bridge/chatgpt-memory.md`
- `templates/rust-service/.ai-bridge/codexpro-project-instructions.md`
- `templates/rust-service/.ai-bridge/current-plan.template.md`
- `templates/rust-service/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/rust-service/.ai-bridge/prompts/handoff-template.md`
- `templates/rust-service/.ai-bridge/prompts/reconnect.md`
- `templates/rust-service/.ai-bridge/prompts/session-bootstrap.md`
- `templates/rust-service/.devcontainer/devcontainer.json`
- `templates/rust-service/.devfleet/bootstrap.sh`
- `templates/rust-service/.devfleet/codexpro-bootstrap.sh`
- `templates/rust-service/.devfleet/codexpro-profile.json`
- `templates/rust-service/.devfleet/codexpro.env.example`
- `templates/rust-service/.devfleet/health-check.sh`
- `templates/rust-service/.devfleet/project-tools.json`
- `templates/rust-service/.devfleet/smoke-test.sh`
- `templates/rust-service/.devfleet/template.json`
- `templates/rust-service/.editorconfig`
- `templates/rust-service/.gitignore`
- `templates/rust-service/Cargo.toml`
- `templates/rust-service/README.md`
- `templates/rust-service/compose.yaml`
- `templates/rust-service/docs/architecture.md`
- `templates/rust-service/src/main.rs`
- `templates/scientific-julia/.ai-bridge/chatgpt-memory.md`
- `templates/scientific-julia/.ai-bridge/codexpro-project-instructions.md`
- `templates/scientific-julia/.ai-bridge/current-plan.template.md`
- `templates/scientific-julia/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/scientific-julia/.ai-bridge/prompts/handoff-template.md`
- `templates/scientific-julia/.ai-bridge/prompts/reconnect.md`
- `templates/scientific-julia/.ai-bridge/prompts/session-bootstrap.md`
- `templates/scientific-julia/.devcontainer/devcontainer.json`
- `templates/scientific-julia/.devfleet/bootstrap.sh`
- `templates/scientific-julia/.devfleet/codexpro-bootstrap.sh`
- `templates/scientific-julia/.devfleet/codexpro-profile.json`
- `templates/scientific-julia/.devfleet/codexpro.env.example`
- `templates/scientific-julia/.devfleet/health-check.sh`
- `templates/scientific-julia/.devfleet/project-tools.json`
- `templates/scientific-julia/.devfleet/smoke-test.sh`
- `templates/scientific-julia/.devfleet/template.json`
- `templates/scientific-julia/.editorconfig`
- `templates/scientific-julia/.gitignore`
- `templates/scientific-julia/README.md`
- `templates/scientific-julia/compose.yaml`
- `templates/scientific-julia/docs/architecture.md`
- `templates/shell-automation/.ai-bridge/chatgpt-memory.md`
- `templates/shell-automation/.ai-bridge/codexpro-project-instructions.md`
- `templates/shell-automation/.ai-bridge/current-plan.template.md`
- `templates/shell-automation/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/shell-automation/.ai-bridge/prompts/handoff-template.md`
- `templates/shell-automation/.ai-bridge/prompts/reconnect.md`
- `templates/shell-automation/.ai-bridge/prompts/session-bootstrap.md`
- `templates/shell-automation/.devcontainer/devcontainer.json`
- `templates/shell-automation/.devfleet/bootstrap.sh`
- `templates/shell-automation/.devfleet/codexpro-bootstrap.sh`
- `templates/shell-automation/.devfleet/codexpro-profile.json`
- `templates/shell-automation/.devfleet/codexpro.env.example`
- `templates/shell-automation/.devfleet/health-check.sh`
- `templates/shell-automation/.devfleet/project-tools.json`
- `templates/shell-automation/.devfleet/smoke-test.sh`
- `templates/shell-automation/.devfleet/template.json`
- `templates/shell-automation/.editorconfig`
- `templates/shell-automation/.gitignore`
- `templates/shell-automation/README.md`
- `templates/shell-automation/compose.yaml`
- `templates/shell-automation/docs/architecture.md`
- `templates/sql-project/.ai-bridge/chatgpt-memory.md`
- `templates/sql-project/.ai-bridge/codexpro-project-instructions.md`
- `templates/sql-project/.ai-bridge/current-plan.template.md`
- `templates/sql-project/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/sql-project/.ai-bridge/prompts/handoff-template.md`
- `templates/sql-project/.ai-bridge/prompts/reconnect.md`
- `templates/sql-project/.ai-bridge/prompts/session-bootstrap.md`
- `templates/sql-project/.devcontainer/devcontainer.json`
- `templates/sql-project/.devfleet/bootstrap.sh`
- `templates/sql-project/.devfleet/codexpro-bootstrap.sh`
- `templates/sql-project/.devfleet/codexpro-profile.json`
- `templates/sql-project/.devfleet/codexpro.env.example`
- `templates/sql-project/.devfleet/health-check.sh`
- `templates/sql-project/.devfleet/project-tools.json`
- `templates/sql-project/.devfleet/smoke-test.sh`
- `templates/sql-project/.devfleet/template.json`
- `templates/sql-project/.editorconfig`
- `templates/sql-project/.gitignore`
- `templates/sql-project/README.md`
- `templates/sql-project/compose.yaml`
- `templates/sql-project/docs/architecture.md`
- `templates/typescript-next/.ai-bridge/chatgpt-memory.md`
- `templates/typescript-next/.ai-bridge/codexpro-project-instructions.md`
- `templates/typescript-next/.ai-bridge/current-plan.template.md`
- `templates/typescript-next/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/typescript-next/.ai-bridge/prompts/handoff-template.md`
- `templates/typescript-next/.ai-bridge/prompts/reconnect.md`
- `templates/typescript-next/.ai-bridge/prompts/session-bootstrap.md`
- `templates/typescript-next/.devcontainer/devcontainer.json`
- `templates/typescript-next/.devfleet/bootstrap.sh`
- `templates/typescript-next/.devfleet/codexpro-bootstrap.sh`
- `templates/typescript-next/.devfleet/codexpro-profile.json`
- `templates/typescript-next/.devfleet/codexpro.env.example`
- `templates/typescript-next/.devfleet/health-check.sh`
- `templates/typescript-next/.devfleet/project-tools.json`
- `templates/typescript-next/.devfleet/smoke-test.sh`
- `templates/typescript-next/.devfleet/template.json`
- `templates/typescript-next/.editorconfig`
- `templates/typescript-next/.gitignore`
- `templates/typescript-next/README.md`
- `templates/typescript-next/app/layout.tsx`
- `templates/typescript-next/app/page.tsx`
- `templates/typescript-next/compose.yaml`
- `templates/typescript-next/docs/architecture.md`
- `templates/typescript-next/package.json`
- `templates/typescript-next/test/smoke.test.js`
- `templates/typescript-next/tsconfig.json`
- `templates/typescript-node/.ai-bridge/chatgpt-memory.md`
- `templates/typescript-node/.ai-bridge/codexpro-project-instructions.md`
- `templates/typescript-node/.ai-bridge/current-plan.template.md`
- `templates/typescript-node/.ai-bridge/prompts/broken-session-recovery.md`
- `templates/typescript-node/.ai-bridge/prompts/handoff-template.md`
- `templates/typescript-node/.ai-bridge/prompts/reconnect.md`
- `templates/typescript-node/.ai-bridge/prompts/session-bootstrap.md`
- `templates/typescript-node/.devcontainer/devcontainer.json`
- `templates/typescript-node/.devfleet/bootstrap.sh`
- `templates/typescript-node/.devfleet/codexpro-bootstrap.sh`
- `templates/typescript-node/.devfleet/codexpro-profile.json`
- `templates/typescript-node/.devfleet/codexpro.env.example`
- `templates/typescript-node/.devfleet/health-check.sh`
- `templates/typescript-node/.devfleet/project-tools.json`
- `templates/typescript-node/.devfleet/smoke-test.sh`
- `templates/typescript-node/.devfleet/template.json`
- `templates/typescript-node/.editorconfig`
- `templates/typescript-node/.gitignore`
- `templates/typescript-node/README.md`
- `templates/typescript-node/compose.yaml`
- `templates/typescript-node/docs/architecture.md`
- `templates/typescript-node/package.json`
- `templates/typescript-node/src/index.ts`
- `templates/typescript-node/test/index.test.ts`
- `templates/typescript-node/tsconfig.json`
- `tests/conftest.py`
- `tests/test_analyzer_v11.py`
- `tests/test_client_generation.py`
- `tests/test_codexpro_hook.py`
- `tests/test_configuration.py`
- `tests/test_dashboard_v11.py`
- `tests/test_docker_modes.py`
- `tests/test_failover.py`
- `tests/test_language_templates.py`
- `tests/test_ollama.py`
- `tests/test_operations_leases.py`
- `tests/test_package_structure.py`
- `tests/test_profiles.py`
- `tests/test_project_safety.py`
- `tests/test_upgrade_preservation.py`
- `tests/test_worktrees_and_v1_restore.py`
- `tools/migrate_config.py`
- `windows/Configure-Ollama.ps1`
- `windows/Migrate-Config.ps1`
- `windows/Set-DevFleetDockerMode.ps1`
- `windows/Test-Ollama.ps1`

## Modified v1.0.0 files

- `CHANGELOG.md`
- `CHECKSUMS.sha256`
- `INSTALL-CHECKLIST.txt`
- `Install-DevFleet.ps1`
- `README-FIRST.md`
- `app/devfleet/analyzer.py`
- `app/devfleet/core.py`
- `app/devfleet/main.py`
- `app/devfleet/projects.py`
- `app/devfleet/status.py`
- `app/static/style.css`
- `app/systemd/devfleet.service`
- `app/templates/index.html`
- `config/devfleet.config.json`
- `docs/00-HARD-STOPS-AND-ASSUMPTIONS.md`
- `docs/01-ARCHITECTURE.md`
- `docs/02-INSTALL-ORDER.md`
- `docs/03-DAILY-USE.md`
- `docs/04-RECOVERY.md`
- `docs/05-SECURITY-MODEL.md`
- `docs/06-CODEXPRO-INTEGRATION.md`
- `docs/07-OFFICIAL-SOURCES.md`
- `linux/bootstrap-compute.sh`
- `linux/devfleet-repair`
- `linux/devfleet-restore-project`
- `linux/devfleet-safe-update`
- `linux/devfleet-user-repair`
- `templates/generic/.devcontainer/devcontainer.json`
- `templates/generic/.devfleet/codexpro-bootstrap.sh`
- `templates/generic/.devfleet/codexpro.env.example`
- `templates/generic/.gitignore`
- `templates/generic/README.md`
- `templates/generic/compose.yaml`
- `templates/node/.devcontainer/devcontainer.json`
- `templates/node/.devfleet/codexpro-bootstrap.sh`
- `templates/node/.devfleet/codexpro.env.example`
- `templates/node/.gitignore`
- `templates/node/README.md`
- `templates/node/compose.yaml`
- `templates/node/package.json`
- `templates/python/.devcontainer/devcontainer.json`
- `templates/python/.devfleet/codexpro-bootstrap.sh`
- `templates/python/.devfleet/codexpro.env.example`
- `templates/python/.gitignore`
- `templates/python/README.md`
- `templates/python/compose.yaml`
- `templates/python/pyproject.toml`
- `tools/Verify-Package.ps1`
- `tools/verify_package.py`
- `windows/02-Provision-ComputeNode.ps1`
- `windows/03-Provision-Vault.ps1`
- `windows/Complete-Cluster.ps1`
- `windows/DevFleet.Common.psm1`
- `windows/Repair-DevFleet.ps1`
- `windows/Update-DevFleet.ps1`

## Removed v1.0.0 files

- None.

## Unchanged v1.0.0 files

- `Bootstrap-Install.ps1`
- `SECURITY-NOTES.txt`
- `START-HERE-DESKTOP.cmd`
- `START-HERE-LAPTOP.cmd`
- `app/devfleet/__init__.py`
- `app/devfleet/auth.py`
- `app/requirements.txt`
- `app/systemd/devfleet-backup.service`
- `app/systemd/devfleet-backup.timer`
- `cloud-init/compute.yaml`
- `cloud-init/vault.yaml`
- `linux/bootstrap-vault.sh`
- `linux/devfleet-backup`
- `linux/devfleet-configure-backup`
- `linux/devfleet-health`
- `linux/devfleet-purge-quarantine`
- `linux/devfleet-set-peer`
- `linux/devfleet-vault-health`
- `linux/devfleet-vault-maintenance`
- `templates/python/src/app/__init__.py`
- `tests/test_analyzer.py`
- `windows/00-Preflight.ps1`
- `windows/01-Install-Prerequisites.ps1`
- `windows/04-Connect-Tailscale.ps1`
- `windows/04a-Connect-WindowsTailscale.ps1`
- `windows/05-Configure-LocalVaultClient.ps1`
- `windows/06-Import-Laptop-Bootstrap.ps1`
- `windows/08-Install-Shortcuts.ps1`
- `windows/09-Export-Laptop-Bootstrap.ps1`
- `windows/10-Export-Desktop-Pairing.ps1`
- `windows/Configure-GitHub.ps1`
- `windows/Export-Diagnostics.ps1`
- `windows/Export-Vault-OfflineCopy.ps1`
- `windows/Invoke-Quarantine-Maintenance.ps1`
- `windows/Invoke-Vault-Maintenance.ps1`
- `windows/Show-DevFleet-Credentials.ps1`
- `windows/Start-DevFleet.ps1`
- `windows/Stop-DevFleet.ps1`
- `windows/Test-DevFleet.ps1`
- `windows/Update-Vault.ps1`

```


## FILE: source/DevFleet-v1.1.0-MIGRATION.md

SHA256: 28666495394ce7fa029bbf0c0d0949512333328d28181fb238bd901345af30f2 | Bytes: 1101 | Git mode: 100644

````
# DevFleet v1.0.0 to v1.1.0 migration

Run the preview and then the upgrade from an elevated PowerShell 7 terminal:

```powershell
pwsh -File .\Upgrade-DevFleet.ps1 -FromVersion 1.0.0 -PreviewOnly
pwsh -File .\Upgrade-DevFleet.ps1 -FromVersion 1.0.0
```

The entry point backs up `C:\ProgramData\DevFleet` configuration, secrets, exports, and package metadata; validates Multipass host-mount isolation; stops each local DevFleet VM; creates a named snapshot; restores the prior running state; previews schema 2; and refreshes only existing instances. It does not delete or recreate VMs, projects, Git repositories, Docker stores/volumes, backup credentials, restic snapshots, vault data, Tailscale identities, SSH keys, dashboard credentials, pairing data, quarantine, or custom values.

A schema-1 baseline becomes Strict/rootless first. Rootless and rootful Docker have separate stores; optional switching requires a report, stopped projects, and explicit rootful acknowledgement. Re-running the v1.1 upgrade is safe and creates another recovery set rather than resetting the selected v1.1 profile.

````


## FILE: source/DevFleet-v1.1.0-VALIDATION.md

SHA256: 9b3a513c9e8dc3a351bcb721eaf6ab05044f1d0583c61f2eaff41e1c88abcd38 | Bytes: 3068 | Git mode: 100644

```
# DevFleet v1.2.1 validation report

## Offline validation completed

The recovered package tree passed the following checks before final archive creation; the release version is 1.2.1.

- **66 focused pytest tests** covering configuration migration, preservation, profiles, Docker-store detection/switching, analyzer policy/cache invalidation, project templates/language metadata, Git worktrees, ownership leases and interrupted transfer, operation progress, dashboard confirmation boundaries, CodexPro bootstrap states, Ollama checks, SSH/Docker-context generation, Windows-host mount prevention, traversal/symlink escapes, backup-before-quarantine, v1 project restoration, and package structure.
- Python bytecode compilation for DevFleet application, tools, and tests.
- Bash syntax checks for Linux helpers and every template hook.
- JSON and JSONC parsing.
- YAML parsing for cloud-init and generated Compose definitions.
- Jinja template parsing.
- FastAPI `/healthz` smoke test.
- All 20 project templates materialized and ran their package-level smoke hook; all 10 core templ