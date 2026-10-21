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

## OS gate of the pwsh profile

`templates/pwsh_profile.ps1.epp` configures PSReadLine only when
`[System.Environment]::OSVersion.Version.Major -ge 10`. A process without a
Windows 10 compatibility manifest is told it runs on Windows 8, so this gate could
skip the configuration silently. `tools/Test-OsGate.ps1` compares what the gate
sees with the real version from CIM, and CI runs it on every Windows runner.

Findings (verified 2026-10-20 on Windows Server 2025, build 26100):

- A .NET Framework executable built without a manifest sees `6.2.9200.0`. The
  concern in the issue is real for such a host.
- Windows PowerShell 5.1 (`powershell.exe`, which embeds a manifest listing
  Windows 10) and PowerShell 7.4.7 (`pwsh.exe`, also manifested) both see
  `10.0.26100.0`, as does CIM.
- The profile is only written to `C:\Program Files\PowerShell\7\profile.ps1`, so
  pwsh 7 is the only host that ever evaluates the gate. The gate is therefore
  reliable for the host it runs on, and was kept as is.

Not verified: Windows Server 2016 and 2019, which were not available. Run
`tools/Test-OsGate.ps1` under pwsh 7 there (see the matrix) before relying on it.

## Manual matrix

Run on each release, with Windows PowerShell 5.1 and PowerShell 7 installed
(MSI, default location):

1. `tools/Test-RenderedPowerShell.ps1` under `powershell.exe` and `pwsh.exe`.
2. `tools/Test-WindowsRuntime.ps1` under `powershell.exe`.
3. `tools/Test-OsGate.ps1` under `pwsh.exe`.
4. `puppet agent -t` with a catalogue that uses `windowspowershell` once, then a
   second time: no resource may change on the second run.

| Release | Parse + PSScriptAnalyzer | Runtime smoke | OS gate | Notes |
| --- | --- | --- | --- | --- |
| Windows Server 2025 | 5.1 and 7.4.7: pass | 5.1: pass | 5.1 and 7.4.7: pass | Manual, 2026-10-20 |
| Windows Server 2022 | CI (`windows-2022`) | CI | CI | Run by `powershell_windows` |
| Windows Server 2019 | not run | not run | not run | To do by hand |
| Windows Server 2016 | not run | not run | not run | To do by hand; check `Get-InstalledModule` and `PowerShellGet` there |
| Windows 10 / 11 | not run | not run | not run | To do by hand |

Update this table when a release is verified.
