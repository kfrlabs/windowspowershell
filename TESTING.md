# Testing

The module is tested at four levels. The first two run on every pull request
(see `.github/workflows/ci.yml`); the last two need a Windows node.

| Level | What it checks | Where |
| --- | --- | --- |
| rspec-puppet | The catalogue compiles, resources and parameters are right | Linux CI (`spec`) |
| Rendered PowerShell | Every script the module sends to a node parses and passes PSScriptAnalyzer | Linux CI (`powershell`), Windows CI (`powershell_windows`) |
| Runtime smoke test | The rendered scripts actually do what they say on a real Windows node | Windows CI (`powershell_windows`) |
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
`Import-Module`), `Unblock-File`, and `ensure => absent`. It is offline and
removes the tree when done.

```powershell
.\tools\Test-WindowsRuntime.ps1 -RenderedPath .rendered-powershell\runtime
```

## Manual matrix

Run on each release, with Windows PowerShell 5.1 and PowerShell 7 installed
(MSI, default location):

1. `tools/Test-RenderedPowerShell.ps1` under `powershell.exe` and `pwsh.exe`.
2. `tools/Test-WindowsRuntime.ps1` under `powershell.exe`.
3. `puppet agent -t` with a catalogue that uses `windowspowershell` once, then a
   second time: no resource may change on the second run.

| Release | Parse + PSScriptAnalyzer | Runtime smoke | Notes |
| --- | --- | --- | --- |
| Windows Server 2025 | 5.1: pass | 5.1: pass | Manual, 2026-10-21 (see below). Double `puppet apply`: no changes on 2nd run. pwsh not installed on the lab host; PowerShell 7 covered by CI (`powershell_windows`, 2022 + 2025). |
| Windows Server 2022 | CI (`windows-2022`) | CI | Run by `powershell_windows` |
| Windows Server 2019 | not run | not run | No lab host; `ltsc2019` container pull failed (disk full on the Docker host). Same PS 5.1 code paths as the validated 2025 run. |
| Windows Server 2016 | not run | not run | No lab host. Sensitive stack (PowerShellGet 1.0.0.1, NuGet 2.8.5.208) present on the 2025 lab host and exercised via `Install-Module PSScriptAnalyzer` from PSGallery. |
| Windows 10 / 11 | not run | not run | To do by hand |

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
