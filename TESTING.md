# Testing

The module is tested at five levels. The first three run on every pull request
(see `.github/workflows/ci.yml`); the last two need a Windows node.

| Level | What it checks | Where |
| --- | --- | --- |
| rspec-puppet | The catalogue compiles, resources and parameters are right | Linux CI (`spec`) |
| Rendered PowerShell | Every script the module sends to a node parses and passes PSScriptAnalyzer | Linux CI (`powershell`), Windows CI (`powershell_windows`) |
| Runtime smoke test | The rendered scripts actually do what they say on a real Windows node | Windows CI (`powershell_windows`) |
| Integration test | A real agent applies a catalogue twice; the second run changes nothing | Windows CI (`integration_windows`) |
| Manual matrix | Windows releases the CI does not offer | By hand, see below |

## Rendered PowerShell

`spec/unit/rendered_powershell_spec.rb` compiles a set of scenarios (in-house
module, external module from a repository and from a source, proxy with and
without credentials, `ensure => absent`) and collects every piece of PowerShell
the `powershell` provider would run: each Exec `command`, `unless` and `onlyif`,
and each profile fragment. It also fails when a template in `templates/` is never
rendered by any scenario, so a new template cannot ship without coverage.

With `WPS_RENDER_DIR` set, the snippets are written there as `.ps1` files:

```shell
bundle exec rake spec_prep
WPS_RENDER_DIR=.rendered-powershell bundle exec rspec --pattern spec/unit/rendered_powershell_spec.rb
pwsh -NoProfile -File tools/Test-RenderedPowerShell.ps1 -Path .rendered-powershell,files
```

`tools/Test-RenderedPowerShell.ps1` parses every file with the language parser of
the host that runs it, then runs PSScriptAnalyzer (errors and warnings, see
`tools/PSScriptAnalyzerSettings.psd1`). Run it under Windows PowerShell 5.1 too:
that is the host the `powershell` provider actually uses.

### Accepted findings

`tools/PSScriptAnalyzerAllowList.psd1` lists the findings that are understood. An
entry only matches when the rule, the file name and the offending source line all
match, and the script reports entries that no longer match anything.

Today there is one: `PSAvoidUsingConvertToSecureStringWithPlainText` on the
`install_*` templates. Building a `PSCredential` from a string is the only way to
hand a proxy password to `Install-Module`, and the secret comes from the Exec
environment (`WPS_PROXY_PASSWORD`), never from the script text. A
`SuppressMessage` attribute is not an option: the provider wraps the script
before it reaches PowerShell, so an attribute at the top would not sit before a
`param` block.

## Runtime smoke test (Windows only)

`tools/Test-WindowsRuntime.ps1` builds a throw-away tree under
`C:\wps-ci\Modules`, then replays the rendered scripts of the `runtime`
scenario the way the provider does (script text on the stdin of
`powershell.exe`): purge of side-by-side versions and its `unless` guard,
manifest creation and update (checked with `Import-PowerShellDataFile` and a real
`Import-Module`), `Unblock-File`, and `ensure => absent`. It also replays the
repository install checks of the `external_from_repository` scenario (sibling
folder from the same render run) against fixture trees, with only their
`$moduleDir` assignment repointed so the real `AllUsers` directory is never
touched: empty, partial (no manifest) and corrupt-manifest version folders
must reinstall (exit 1), while a healthy `New-ModuleManifest` tree satisfies
the check (exit 0). A syntactically broken script in `Functions/` must fail
the manifest build (exit non-zero, naming the file and line) while the
`.psd1` stays byte-identical, and the build goes green again once the script
is removed. It is offline and
removes the tree when done.

```powershell
.\tools\Test-WindowsRuntime.ps1 -RenderedPath .rendered-powershell\runtime
```

## Integration test (Windows only, issue #84)

`tools/Test-PuppetApply.ps1` is the real-agent counterpart of the offline
replay above: it runs `puppet apply` on `spec/integration/site.pp`, then
applies the same catalogue a second time. The first run may change resources
(exit code 2 with `--detailed-exitcodes`); the second must change nothing
(exit code 0). Functional checks then verify the converged state: the
manifest version and its nested modules, an `Import-Module` round-trip of
both modules, and the profile import line.

The catalogue is minimal and offline on purpose: an in-house module deployed
by bulk copy (`source`), one script deployed by `content`, one third-party
module deployed by file copy (`source` backend), and one profile import. It
exercises what the other levels cannot: a real agent compiling the catalogue,
ordering `File`/`Exec`/`Concat` resources, firing the
manifest-regeneration notifies, and rejecting duplicate resources. The file
sources are served from the `wps_integration` fixture module
(`spec/integration/modules/wps_integration`), so the `files/` payload shipped
to the Forge stays clean and no Gallery or NuGet access is needed.

The CI `integration_windows` job (Windows Server 2022 and 2025) installs
Puppet agent 8, stages this checkout as `windowspowershell` next to the
pinned Forge dependencies (same versions as `.fixtures.yml`) and the fixture
module under `C:\wps-int\modules`, stops the agent service so it cannot
contend for the run lock, then runs:

```powershell
.\tools\Test-PuppetApply.ps1 -Site spec\integration\site.pp -Modulepath C:\wps-int\modules
```

To run the same check on a lab node (Puppet 8, Windows PowerShell 5.1), copy
the checkout and the fixture module to the node, stage them the same way
(`C:\wps-int\modules\windowspowershell` plus the pinned dependencies and
`wps_integration`), create the module-root parent (`C:\wps-int` already
exists there), then run the script. On a node enrolled to an agent
environment that does not exist locally (e.g. `environment=saim` in
`puppet.conf`), pass `-Environment production`. Run the apply as a Scheduled
Task as SYSTEM: the SSH channel cannot host the `powershell` provider's
stdin.

## Repository backend test (Windows only, issue #85)

`tools/Test-RepositoryBackend.ps1` closes the gap the integration test above
leaves: the `repository` backend (`Install-Module` as SYSTEM) never ran for
real. The script builds a minimal `WpsRepoTest 1.0.0` module, registers a
local file repository `WpsLocal` for the account running the script, publishes
the module into it (`Publish-Module -Force`: without `-Force` the NuGet
bootstrap prompt throws `ShouldContinue` when non-interactive), then applies
`spec/integration/site_repository.pp` twice. Before the first apply it seeds
an empty `WpsRepoTest\1.0.0` version folder, the way an interrupted install
leaves one behind (issue #106): the empty folder must not satisfy the install
check, so the first run reinstalls it (exit 2) and the second changes nothing
(exit 0). Functional checks
verify `Get-InstalledModule`, the `AllUsers` layout and an `Import-Module`
round-trip.

Two findings from the first SYSTEM run are now enforced or documented:

- `Register-PSRepository` is per-user: a repository registered interactively
  is invisible to the agent (`Unable to find repository 'WpsLocal'`). Register
  it as SYSTEM (this script does it when run as SYSTEM) on every node.
- `Install-Module -Scope AllUsers` always installs to
  `C:\Program Files\WindowsPowerShell\Modules` and ignores a custom
  `module_root`: combining `repository` with a custom root now fails
  compilation instead of reinstalling on every run.

The CI `integration_repository_windows` job (Windows Server 2022 and 2025)
runs:

```powershell
./tools/Test-RepositoryBackend.ps1 -Site spec/integration/site_repository.pp -Modulepath 'C:\wps-int\modules'
```

as SYSTEM (the job runs on the runner, whose default account sees the
locally registered repository). To run it on a lab node, stage the checkout
as for the integration test, then run the script as a Scheduled Task as
SYSTEM.

## Proxy test (Windows only, issue #85)

`tools/Test-ProxyBackend.ps1` validates `-Proxy` / `-ProxyCredential` for
real: it starts a minimal authenticating CONNECT proxy on 127.0.0.1, then
`Find-Module` (and, best-effort, `Save-Module` — same PackageManagement
download path as `Install-Module`, without polluting `AllUsers`) against the
real PowerShell Gallery through it. Good credentials succeed; a `file://`
repository ignores `-Proxy` (no HTTP involved, expected). Run it as SYSTEM on
a node with Gallery access:

```powershell
./tools/Test-ProxyBackend.ps1
```

Manual validation 2026-10-23 (LAB-WINDOCKER-01, Windows Server 2025, 5.1):
`Find-Module PSScriptAnalyzer` through the local authenticating proxy as
SYSTEM succeeds; the proxy log shows `407` without credentials and
`TUNNEL-OK` with them. `Save-Module` through the same proxy establishes
tunnels but can stall on the post-download publisher check, so it runs
best-effort with a timeout (TEST1 already proves the proxy path).

## Non-ASCII encoding (Windows PowerShell 5.1, issue #89)

`Windowspowershell::Name` accepts non-ASCII (`Café-Tools` is in the type
spec), and `windowspowershell::script` writes `content` verbatim. Puppet
`File`/`Concat` resources serialize that text as UTF-8 **without** a BOM,
and Windows PowerShell 5.1 decodes a BOM-less file with the system ANSI
code page instead. The linter (`tools/Test-RenderedPowerShell.ps1`) reads
every file explicitly as UTF-8, so CI never sees the corruption -- only a
real 5.1 host does.

Manual verification 2026-10-24 (Windows Server 2025, 5.1.26100.33438):

- Host `LAB-WINDOCKER-01` (Docker Windows): a `café èè ü` string written
  as UTF-8 without BOM dot-sources under 5.1 as 19 characters
  (`99 97 102 101 195 169 ...`, the UTF-8 bytes `C3 A9` read as two ANSI
  characters) instead of 15 (`... 233 ...` for `é`); the same bytes with
  a BOM read back correctly. Byte-level proof that 5.1 follows the BOM.
- Host `LAB-WIN-01` (Puppet 8.31.0 agent): catalogue with
  `windowspowershell::module { 'Café-Tools': }` and
  `windowspowershell::script { 'Get-CaféTest': content => "function
  Get-CaféTest { 'café èè ü' }\n" }`, applied twice as SYSTEM (Scheduled
  Task, the SSH channel cannot host the `powershell` provider's stdin).
  First run exits 2 (module tree, root module, witness, manifest creation
  and the `update-manifest`/`unblock-files` refreshes all converge);
  second run exits 0 (fully idempotent -- the encoding changes nothing
  about convergence). The deployed `Get-CaféTest.ps1` is 43 bytes, UTF-8,
  no BOM (`... 43 61 66 C3 A9 ...`, `hasBOM=False`); the `Café-Tools`
  directory and the manifest `NestedModules` entry
  (`Functions\Get-CaféTest.ps1`) keep the `é`. `Import-Module Café-Tools`
  succeeds, but the exported function is registered under its mojibake
  spelling (`Get-CafÃ©Test`), so calling `Get-CaféTest` fails with
  `CommandNotFoundException`.

Conclusion (documented limitation, no code change): keep module names,
script names and script content ASCII-only wherever Windows PowerShell
5.1 may run the agent. Files deployed from a `source` (bulk module copy,
external-module file copy) are byte-copies -- save them ASCII-only (or
UTF-8 with BOM, which 5.1 honours) at the source. PowerShell 7 reads
BOM-less UTF-8 correctly, so the limitation is specific to the 5.1 host
running the agent. See [Limitations](README.md#limitations).

## Release gate

Pushing a `v*.*.*` tag runs `.github/workflows/release.yml`: `verify` (tag,
syntax, lint, metadata) plus `spec` (rspec-puppet on the release matrix),
then the `verify_ci` gate, then the `forge` publish job.

`verify_ci` does not re-run the Windows jobs. It queries the check-runs API
for this exact commit and requires at least one `completed` / `success` run
of the `Test suite` check from `ci.yml` (the aggregator over lint, spec,
PowerShell, Windows runtime/integration and module build). In-progress,
cancelled or superseded runs fail closed and block the release; only a green
`Test suite` lets the tag publish.

If the gate blocks a tag: push the commit to `main`, let CI go green, then
move the tag onto the green commit and push it again.

## Manual matrix

Run on each release, with Windows PowerShell 5.1 and PowerShell 7 installed
(MSI, default location):

1. `tools/Test-RenderedPowerShell.ps1` under `powershell.exe` and `pwsh.exe`.
2. `tools/Test-WindowsRuntime.ps1` under `powershell.exe`.
3. `puppet agent -t` with a catalogue that uses `windowspowershell` once, then a
   second time: no resource may change on the second run.

| Release | Parse + PSScriptAnalyzer | Runtime smoke | Integration (`apply` twice) | Notes |
| --- | --- | --- | --- | --- |
| Windows Server 2025 | 5.1: pass | 5.1: pass | CI (`windows-2025`) | Manual, 2026-10-21 (see below). pwsh not installed on the lab host; PowerShell 7 covered by CI (`powershell_windows`, 2022 + 2025). |
| Windows Server 2022 | CI (`windows-2022`) | CI | CI (`windows-2022`) | Run by `powershell_windows` + `integration_windows` |
| Windows Server 2019 | not run | not run | not run | Claimed in `metadata.json` but still to be tested/confirmed (issue #87). No lab host yet; `ltsc2019` container pull failed (disk full on the Docker host). Same PS 5.1 code paths as the validated 2025 run. |
| Windows 11 | not run | not run | not run | Claimed in `metadata.json` but still to be tested/confirmed (issue #87). To do by hand. Windows 10 is no longer supported (end of support 14/10/2025, outside LTSC/ESU) and has been removed from `metadata.json`. |

Update this table when a release is verified.

### Manual validation 2.0.0 (2026-10-21)

Host `LAB-WIN-01`: Windows Server 2025 Standard (build 26100),
Windows PowerShell 5.1.26100.33438, Puppet 8.31.0, PowerShellGet 1.0.0.1,
PackageManagement 1.0.0.1, NuGet provider 2.8.5.208. Module under test is the
release branch at `origin/main` plus this CHANGELOG/TESTING update;
dependencies from the Forge (stdlib 9.7.0, concat 9.1.0, powershell 6.2.0).

1. Parse + PSScriptAnalyzer under `powershell.exe`:
   `Test-RenderedPowerShell.ps1 -Path .rendered-powershell,files` —
   80 files, 0 parse errors, PSScriptAnalyzer 1.25.0 with 0 findings after the
   allow-list (the `ConvertToSecureStringWithPlainText` entry matches the
   `install_*` templates as expected).
2. Runtime smoke under `powershell.exe`:
   `Test-WindowsRuntime.ps1 -RenderedPath .rendered-powershell\runtime` — OK
   (23 checks: purge idempotence, manifest create/update, `Import-Module`
   round-trip, `ensure => absent`).
3. Double `puppet apply` (run as a Scheduled Task as SYSTEM, the SSH channel
   cannot host the `powershell` provider's stdin): catalogue with
   `windowspowershell::module { 'WpsTest': version => '1.0', ... }` plus a
   `windowspowershell::script` — first run creates the module tree, the
   `.manifest-params` witness and the manifest; second run applies the catalog
   with no resource changes.

### Production rollout / profile rollback (issue #108, pending lab verification)

Procedure to verify the [Production rollout](README.md#production-rollout)
guide on a lab node (Puppet 8, run as a Scheduled Task as SYSTEM).
Not yet run: no Windows node is reachable from this checkout, so the steps
below are the procedure to run, not a report.

1. Pre-flight: record the SHA-256 of each existing profile (when present),
   the `PSModulePath` entries, the ACL of the module root, and the module
   root listing:
   ```powershell
   Get-FileHash C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1 -ErrorAction SilentlyContinue
   Get-FileHash C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1 -ErrorAction SilentlyContinue
   Get-FileHash 'C:\Program Files\PowerShell\7\profile.ps1' -ErrorAction SilentlyContinue
   $env:PSModulePath -split ';'
   (Get-Acl 'C:\Program Files\WindowsPowerShell\Modules').Access
   Get-ChildItem 'C:\Program Files\WindowsPowerShell\Modules'
   ```
   With a custom `module_root`, substitute that path for
   `C:\Program Files\WindowsPowerShell\Modules` in the `Get-Acl` (and module
   listing) commands above.
2. Apply the pilot catalogue (`manage_profiles => false`, the default)
   twice with `puppet apply --detailed-exitcodes`: no profile/`concat`
   resources change (overall second-run exit 0 on a converged node), and
   the profile hashes from step 1 are unchanged.
3. Opt in (`manage_profiles => true`) and apply twice: the first run exits
   2 (profiles rebuilt from fragments), the second exits 0 (no changes).
4. Roll back (`manage_profiles => false`) and apply once: no profile/`concat`
   resources change (overall exit 0, no `concat` target declared), and each
   `profile.ps1` hash matches the post-step-3 value -- the files stay as-last-written,
   unmanaged. Clean up by hand-deleting the left-over files or by
   re-managing (`manage_profiles => true`).
