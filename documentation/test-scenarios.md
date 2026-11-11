# Test scenarios

<!-- Generated from spec/acceptance/scenarios.yaml by `ruby spec/acceptance/scenarios.rb --format markdown --write`. Do not edit by hand. -->

Scenarios for install, upgrade, downgrade, rollback, failover, migration and node replacement, 
taken from support cases and Jira tickets about peadm. Each has the versions from the report and, 
where the exact customer version is not worth installing, an equivalent that CI can run.

| Status | Meaning |
|---|---|
| ci | runs on pull requests |
| ci-partial | a PR workflow runs the same path but does not inject the fault |
| ci-manual | workflow exists, run it on demand with workflow_dispatch |
| manual | acceptance plan exists and is run by hand on operator VMs; no workflow |
| unit | covered by rspec only |
| new | needs an acceptance plan written |
| repro-only | needs an environment or fault we cannot script yet |

| ID | Category | Versions | Architecture | Status | Pri | Scenario |
|---|---|---|---|---|---|---|
| [I-01](#i-01) | install | 2025.12.1 | standard-with-dr, large, extra-large-with-dr | ci | P1 | Fresh install, supported architectures |
| [I-02](#i-02) | install | 2025.12.1 | standard-with-dr | new | P1 | Install with a non-production environment for PE node groups |
| [U-01](#u-01) | upgrade | 2023.8.8 → 2025.12.0 (CI: 2023.8.13 → 2025.12.1) | standard | ci-partial | P1 | Skip-line upgrade 2023.8 to 2025.12 (pe-puppetdb reload flake) |
| [U-02](#u-02) | upgrade | 2025.10.0 → 2025.11.3 | standard-with-dr | new | P2 | Upgrade with Code Manager over SSH and an unknown r10k host key |
| [U-03](#u-03) | upgrade | 2023.8.13 → 2025.12.1 | standard | new | P1 | Truncated or corrupt installer tarball |
| [U-04](#u-04) | upgrade | 2025.11.0 → 2025.11.2 | standard | new | P2 | Upgrade then eyaml decryption fails (empty-DN PKCS7 certificate) |
| [U-05](#u-05) | upgrade | 2025.8.x → 2025.11.x | large | new | P2 | Post-upgrade corrective changes and compiler status |
| [U-06](#u-06) | upgrade | 2023.0.0 → 2023.8.9 | large-with-dr | new | P2 | Upgrade a 2023.0 cluster with replica and compilers |
| [U-07](#u-07) | upgrade | 2021.7.0 → 2023.8.9 | large | new | P2 | Two-hop upgrade of a lab cluster not yet managed by peadm |
| [U-08](#u-08) | upgrade | 2023.8.6 → 2023.8.9 (CI: 2023.8.13 → 2023.8.13) | large | new | P2 | Patch-level upgrade must bring compilers along |
| [U-09](#u-09) | upgrade | 2023.8.x → 2023.8.8 (CI: 2025.12.1 → 2026.0.1) | extra-large-with-dr | ci-partial | P2 | Upgrade with legacy compilers and the legacy OID extension |
| [U-10](#u-10) | upgrade | 2023.8.10 → 2023.8.12 | standard | new | P3 | Patch upgrade to add target OS support |
| [U-11](#u-11) | upgrade | 2025.8.x → 2025.10.x | standard | repro-only | P3 | Installer pre-check cannot find is_cloud_database.rb |
| [U-12](#u-12) | upgrade | 2025.11.3 → 2025.12.0 | standard | unit | P1 | Target version newer than the module supports |
| [U-13](#u-13) | upgrade | 2025.12.1 → 2026.0.1 | standard | manual | P1 | Resume an n to n+1 upgrade after an injected failure |
| [D-01](#d-01) | downgrade | 2025.11.3 → 2025.10.0 | standard | unit | P1 | Downgrade attempt is blocked early |
| [R-01](#r-01) | rollback | 2023.8.8 → 2023.8.9 (CI: 2023.8.13 → 2025.12.1) | standard-with-dr | new | P1 | Roll back a failed upgrade from a peadm backup |
| [R-02](#r-02) | rollback | 2025.11.0 → 2025.11.2 | standard | new | P2 | Roll back by VM snapshot after a bad upgrade |
| [F-01](#f-01) | failover | 2023.8.13 | standard-with-dr | new | P1 | Planned role swap on 2023.8 |
| [F-02](#f-02) | failover | 2025.12.1 | standard-with-dr | new | P1 | Planned role swap on 2025.x, and on a mixed estate |
| [F-03](#f-03) | failover | 2025.12.1 | extra-large-with-dr | ci-manual | P1 | Unplanned failure of the primary |
| [F-04](#f-04) | failover | 2025.10.0 | standard-with-dr | new | P2 | Role swap across an OS upgrade (mixed OS pair) |
| [F-05](#f-05) | failover | 2023.8.x | standard-with-dr | repro-only | P2 | Cert-loading timeout while repurposing the old primary |
| [M-01](#m-01) | migrate | 2023.8.8 → 2023.8.9 (CI: 2025.12.1 → 2026.0.1) | standard | ci-partial | P2 | Migrate to a new OS and version |
| [M-02](#m-02) | migrate | 2025.12.1 | standard-with-dr | new | P1 | Backup, restore and migrate with a non-production environment |
| [M-03](#m-03) | migrate | 2025.6.x | standard | repro-only | P3 | New stack built on an existing shared CA |
| [B-01](#b-01) | backup-restore | 2026.0.1 | extra-large | ci | P1 | Backup and restore |
| [C-01](#c-01) | compiler | 2025.12.1 | large-with-dr | new | P1 | Replace a compiler when the A/B pins are duplicated |
| [C-02](#c-02) | convert | 2023.8.x | large-with-dr | new | P2 | Convert a cluster with several compilers |
| [P-01](#p-01) | replica | 2023.8.13 | standard-with-dr | ci-partial | P1 | Re-add a replica after the VM was auto-replaced |
| [DB-01](#db-01) | database | 2025.12.1 | extra-large-with-dr | ci-partial | P1 | Replace a failed PostgreSQL node, including the primary-side one |

## I-01

**Fresh install, supported architectures**

- Source: control
- Architecture: standard-with-dr, large, extra-large-with-dr
- OS: almalinux-8
- Workflow: `test-install-matrix.yaml`

Reproduce:

1. provision_test_cluster, then install_test_cluster for each architecture
2. repeat for 2023.8.13, 2025.12.1 and 2026.0.1 (also RHEL 9 and RHEL 8 FIPS)

Expected:

- install completes and peadm::status reports operational

## I-02

**Install with a non-production environment for PE node groups**

- Source: PE-39789, PE-39465, PE-46598
- Architecture: standard-with-dr
- Fault: node_group_environment set to an environment that is not "production"

Reproduce:

1. install with node_group_environment=dev and no production environment on disk
2. run peadm::status, add_replica, add_compilers, backup

Expected:

- every plan uses the configured environment and none assumes "production"

## U-01

**Skip-line upgrade 2023.8 to 2025.12 (pe-puppetdb reload flake)**

- Source: CASE-002, GJira-1
- Architecture: not stated in the report; tested as standard
- Fault: first reload of pe-puppetdb fails during `puppet infrastructure configure`
- Workflow: `test-upgrade-matrix.yaml`

Reproduce:

1. install 2023.8.x, then peadm::upgrade to 2025.12.x
2. to inject the fault, add a systemd drop-in on the primary that makes pe-puppetdb ExecReload fail once (for example a script that exits 1 the first time and 0 afterwards)
3. the report shows installer exit code 6 on the first attempt and a successful reload on later attempts

Expected:

- failure message includes the installer log tail and the failed unit status
- (planned) one automatic retry of the configure run, then resume

## U-02

**Upgrade with Code Manager over SSH and an unknown r10k host key**

- Source: CASE-008
- Architecture: not stated in the report; tested as standard-with-dr
- Fault: Code Manager remote is git over SSH and its host key is not in known_hosts

Reproduce:

1. configure Code Manager with an SSH r10k remote and no r10k_known_hosts
2. upgrade; then `puppet code deploy production --wait`

Expected:

- preflight warns before the upgrade; post-flight deploy check fails loudly with "invalid or unknown remote ssh hostkey"

## U-03

**Truncated or corrupt installer tarball**

- Source: PE-42686, CASE-049, PE-43373
- Architecture: standard
- Fault: installer tarball truncated after download, or named differently from puppet-enterprise-<ver>-<platform>.tar.gz

Reproduce:

1. stage a truncated tarball at uploaddir, use download_mode=direct with pe_installer_source pointing at it
2. run peadm::upgrade

Expected:

- fails in preparation with a clear message, before Puppet or any PE service is stopped

## U-04

**Upgrade then eyaml decryption fails (empty-DN PKCS7 certificate)**

- Source: CASE-012, GJira-7
- Architecture: standard
- Fault: eyaml key pair created with `eyaml createkeys --pkcs7-subject '/'`

Reproduce:

1. create eyaml keys with an empty subject, add an ENC[PKCS7,...] value to Hiera data, confirm a catalog compiles on 2025.11.0
2. upgrade to 2025.11.2 and compile a catalog that looks the value up

Expected:

- (planned) preflight known-issue rule flags the key and the target version
- post-flight catalog compile fails the run instead of reporting success

Notes: GJira-7 (vendored hiera-eyaml 5.0.1) closed this in PE itself; keep the scenario as the template for known-issue rules.

## U-05

**Post-upgrade corrective changes and compiler status**

- Source: CASE-017
- Architecture: large

Reproduce:

1. install 2025.8 with two compilers, upgrade with peadm::upgrade
2. run puppet on the primary twice; reboot the primary; read Puppet Services status

Expected:

- second Puppet run on every infrastructure node reports zero changes
- compilers report healthy after a reboot

## U-06

**Upgrade a 2023.0 cluster with replica and compilers**

- Source: CASE-035, CASE-034
- Architecture: large-with-dr
- Fault: replica `puppet infrastructure status` reports compilers unreachable

Reproduce:

1. install large-with-dr on 2023.0.0 (older peadm layout, may need convert)
2. run peadm::status against both primary and replica

Expected:

- preflight reports the replica's view of compilers as a failure, with the likely cause, rather than leaving the operator to open a case

## U-07

**Two-hop upgrade of a lab cluster not yet managed by peadm**

- Source: CASE-039, CASE-040
- Architecture: large

Reproduce:

1. install 2021.7.0 with the PE installer (not peadm) plus one compiler
2. peadm::convert, upgrade to 2023.0.0, then upgrade to 2023.8.9

Expected:

- each hop passes; the plan states the supported hop when a skip is unsafe

## U-08

**Patch-level upgrade must bring compilers along**

- Source: CASE-045
- Architecture: large
- Fault: none; the customer ran the PE installer on the primary only

Reproduce:

1. install 2023.8.6 with compilers
2. upgrade with peadm::upgrade (and, for contrast, with the bare installer)

Expected:

- peadm::upgrade leaves every infrastructure node on the same PE and agent version
- the bare-installer path shows the "compiler has a PE version of ..." error

Notes: CI has no earlier patch of 2023.8 to install; confirm an older installable patch before scheduling.

## U-09

**Upgrade with legacy compilers and the legacy OID extension**

- Source: CASE-050, GJira-17, PE-40239, PE-36355, PE-36212
- Architecture: extra-large-with-dr
- CI runs: large-with-dr with one legacy compiler (what test-legacy-upgrade.yaml runs)
- Fault: compilers carry the legacy compiler OID (1.3.6.1.4.1.34380.1.1.9814) set to false
- Workflow: `test-legacy-upgrade.yaml`

Reproduce:

1. install with legacy compilers, set the 9814 extension to false on them
2. run peadm::upgrade

Expected:

- the legacy-compiler check explains what it found and what to do

## U-10

**Patch upgrade to add target OS support**

- Source: CASE-001
- Architecture: not stated in the report; tested as standard
- OS: ubuntu-2404

Reproduce:

1. install 2023.8.x on Ubuntu, upgrade to the patch release

Expected:

- {"control scenario"=>"succeeds"}

Notes: no Ubuntu lane exists in CI today.

## U-11

**Installer pre-check cannot find is_cloud_database.rb**

- Source: CASE-046
- Architecture: not stated in the report; tested as standard

Reproduce:

1. cause is not stated in the report. Start by running the plan with a tarball staged by hand and compare the extracted tree

Expected:

- preflight catches a damaged or mismatched installer before upgrade

## U-12

**Target version newer than the module supports**

- Source: CASE-003, PE-47850
- Architecture: standard
- Fault: module's newest supported version is older than the target

Reproduce:

1. run assert_supported_pe_version with a target beyond the module's newest

Expected:

- fails with a message that says which peadm release adds support

## U-13

**Resume an n to n+1 upgrade after an injected failure**

- Source: CASE-002, CASE-011
- Architecture: standard
- Fault: post-installer variant, a site.pp that fails catalog compilation is planted so the Puppet run after the installer fails; installer variant, a pe-puppetdb systemd drop-in makes the first reload fail

Reproduce:

1. install with `bolt plan run peadm_spec::install_test_cluster architecture=standard version=2025.12.1 code_manager_auto_configure=true console_password="$CONSOLE_PASSWORD" --inventoryfile <inventory> --modulepath spec/fixtures/modules`
2. record the node facts with `bolt plan run peadm_spec::foundation_node_checks --inventoryfile <inventory> --modulepath spec/fixtures/modules`
3. gate, run `bolt plan run peadm_spec::upgrade_with_injected_failure version=2026.0.1 fault=post-installer --inventoryfile <inventory> --modulepath spec/fixtures/modules` (the first peadm::upgrade fails after the installer, the plan removes the fault and resumes at upgrade-node-groups; it returns resume_ok true)
4. repeat foundation_node_checks on the upgraded primary
5. UPG-04 baseline, rebuild at 2025.12.1 and run the same plan with `fault=installer` (resumes at upgrade-primary; today the resume is expected to fail because pe_install deletes the tarball)
6. cleanup after an interrupted run, restore /root/peadm_spec_site.pp.orig over the site.pp it came from (code-staging when Code Manager is on) and commit it with `puppet-code file-sync commit`, or delete the pe-puppetdb drop-in /etc/systemd/system/pe-puppetdb.service.d/peadm-spec-fault.conf and run `systemctl daemon-reload`

Expected:

- after the first upgrade fails, resuming at upgrade-node-groups completes the upgrade and peadm_spec::upgrade_with_injected_failure returns resume_ok true
- the fault is gone from the node afterwards and the primary reports the target version
- (planned) UPG-04, the installer variant resumes at upgrade-primary and completes instead of failing for want of the installer tarball

Notes: Run by hand (decision D-13); peadm::upgrade has no test knob (D-14). A PE version pair other than 2025.12.1 and 2026.0.1 can be passed as plan parameters.

## D-01

**Downgrade attempt is blocked early**

- Source: CASE-009
- Architecture: not stated in the report; tested as standard
- Fault: target version is older than the installed version

Reproduce:

1. on an installed 2025.11.3 cluster run peadm::upgrade version=2025.10.0

Expected:

- fails before any service is stopped; message points to restore-from-backup
- the installer's own rule is chronological (release date), not only the version number, so a lower number can also be refused

## R-01

**Roll back a failed upgrade from a peadm backup**

- Source: CASE-036, CASE-009
- Architecture: not stated in the report; tested as standard-with-dr
- Fault: upgrade stopped partway (for example kill the plan after upgrade-primary)

Reproduce:

1. peadm::backup, then peadm::upgrade; interrupt after upgrade-primary
2. attempt recovery to the starting version

Expected:

- (planned) peadm::rollback reinstalls the previous version, restores the backup, rebuilds replica and compilers and verifies
- today this is not possible without manual steps

## R-02

**Roll back by VM snapshot after a bad upgrade**

- Source: CASE-012
- Architecture: standard

Reproduce:

1. snapshot the primary, upgrade, hit a regression (see U-04), revert

Expected:

- (planned) snapshot hook runs before upgrade and on rollback
- after revert the cluster verifies clean and agents resume

## F-01

**Planned role swap on 2023.8**

- Source: CASE-015, CASE-023, CASE-029, PE-43987
- Architecture: standard-with-dr

Reproduce:

1. promote the replica, uninstall PE on the old primary, install the agent, add it back as the replica with peadm::add_replica
2. run peadm::status and a code deploy from the new primary

Expected:

- the new primary classifies correctly and availability groups follow the hosts

Notes: test-failover.yaml is an unplanned failover (primary shut down), not a planned swap.

## F-02

**Planned role swap on 2025.x, and on a mixed estate**

- Source: CASE-023
- Architecture: standard-with-dr

Reproduce:

1. repeat F-01 on 2025.12.x
2. separately confirm the same steps work when production is still 2023.8 and non-production is 2025.x (the customer rehearsed on the newer line)

Expected:

- same procedure on both lines

Notes: test-failover.yaml is an unplanned failover (primary shut down), not a planned swap.

## F-03

**Unplanned failure of the primary**

- Source: CASE-015, PE-39742
- Architecture: extra-large-with-dr
- Fault: primary powered off
- Workflow: `test-failover.yaml`

Reproduce:

1. run test-failover.yaml, which shuts down the primary, deletes its certname from the primary PostgreSQL node, runs `puppet infra promote replica`, then adds a spare replica

Expected:

- (planned) peadm::failover does the promote and re-asserts classification
- the cluster verifies clean before the replacement replica exists

## F-04

**Role swap across an OS upgrade (mixed OS pair)**

- Source: CASE-024, CASE-048
- Architecture: standard-with-dr
- OS: ubuntu-2204 primary with ubuntu-2404 replica

Reproduce:

1. rebuild the replica on Ubuntu 24.04, swap roles, rebuild the old primary on 24.04
2. agents point at a load balancer or DNS name; no server_list on agents

Expected:

- agents reach the new primary with their existing certificates
- mixed-OS window is a documented, tested state

## F-05

**Cert-loading timeout while repurposing the old primary**

- Source: CASE-029, GJira-11, CASE-047
- Architecture: standard-with-dr
- Fault: slow CA responses while the old primary is rebuilt as a replica

Reproduce:

1. cause is documented only as a timeout in an earlier APAC exercise; reproduce by adding latency to CA requests on the new primary

Expected:

- CA query timeouts are configurable and the plan resumes cleanly

## M-01

**Migrate to a new OS and version**

- Source: CASE-048, CASE-038
- Architecture: not stated in the report; tested as standard
- OS: rocky-8 to rocky-9 (CI uses almalinux)
- Workflow: `test-migration.yaml`

Reproduce:

1. peadm::migrate from the old primary to new hosts on the new OS
2. check /etc/yum.repos.d/pe.repo on agents afterwards

Expected:

- agents keep resolving the pe_repo name they were built with

## M-02

**Backup, restore and migrate with a non-production environment**

- Source: PE-46598, PE-45758
- Architecture: standard-with-dr
- Fault: infrastructure uses an environment other than production; default classifier groups customised

Reproduce:

1. run backup and restore, then migrate, on a cluster from I-02

Expected:

- default classifier groups are restored with their classification

## M-03

**New stack built on an existing shared CA**

- Source: CASE-044
- Architecture: standard
- Fault: console-cert and saml-cert already exist on the shared CA

Reproduce:

1. stand up a CA from a 2023.8 stack, then install a new stack that points at it

Expected:

- documented as supported or unsupported; today the installer cannot reissue the internal certificates

## B-01

**Backup and restore**

- Source: control, PE-36230
- Architecture: extra-large
- OS: almalinux-8
- Workflow: `test-backup-restore.yaml`

Reproduce:

1. test_backup then test_restore

Expected:

- restored cluster passes peadm::status

## C-01

**Replace a compiler when the A/B pins are duplicated**

- Source: CASE-016, PE-43572, CASE-042
- Architecture: large-with-dr
- Fault: two nodes pinned to availability group A in the PuppetDB database node group

Reproduce:

1. pin a second node to group A in PE PuppetDB Database, run peadm::add_compilers

Expected:

- preflight names the duplicate pin and the fix before anything changes
- (planned) repair_classification fixes it

## C-02

**Convert a cluster with several compilers**

- Source: CASE-041, PE-44017, PE-41637
- Architecture: large-with-dr
- Fault: compiler group lists three puppetdb hosts but two ports

Reproduce:

1. run peadm::convert on a large-with-dr cluster with three compilers; then compile on a compiler

Expected:

- pe_format_urls does not fail; hosts and ports match

## P-01

**Re-add a replica after the VM was auto-replaced**

- Source: CASE-022, PE-43490
- Architecture: standard-with-dr
- Fault: replica VM recreated with the same certname without a forget first
- Workflow: `test-add-replica-matrix.yaml`

Reproduce:

1. delete and recreate the replica VM, run peadm::add_replica

Expected:

- run does not report success while the replica is unclassified or absent from `puppet infrastructure status`

## DB-01

**Replace a failed PostgreSQL node, including the primary-side one**

- Source: CASE-020, PE-41341
- Architecture: extra-large-with-dr
- Fault: failed_postgresql_host equals primary_postgresql_host; replacement lacks trusted extensions
- Workflow: `test-replace-failed-postgresql.yaml`

Reproduce:

1. destroy the primary PostgreSQL node and run peadm::replace_failed_postgresql

Expected:

- replacement is classified as a PostgreSQL node and rejoins as a replica
