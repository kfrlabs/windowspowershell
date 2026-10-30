<#
.SYNOPSIS
    Validates the repository backend against a local file repository.

.DESCRIPTION
    Offline counterpart of the Gallery path that issue #85 found never
    exercised: registers a local file PSRepository (visible to the account
    running this script — run it as SYSTEM, the Puppet agent account, via a
    Scheduled Task: Register-PSRepository is per-user and a repository
    registered interactively is invisible to the agent), publishes a minimal
    WpsRepoTest 1.0.0 module and, with -IncludeBrackets, a literal
    Bracket[Beta] 1.0.0 module (the
    Gallery has no bracketed names, so only a file repo can prove the
    wildcard-escaped install path — issue #112, Gap 2) into it, then applies
    the site catalogue passed via -Site twice with `puppet apply
    --detailed-exitcodes`. The first run may change resources (exit 2); the
    second must change nothing (exit 0). A third cycle then proves a partial
    install (files without a manifest, the way an interrupted install leaves
    one behind — issue #112, Gap 5) reinstalls for real. Functional checks
    verify the converged state: Get-InstalledModule, directory layout,
    Import-Module round-trips. Installed versions are uninstalled at the end
    so the node is left as found.

    Run from Windows PowerShell 5.1, the host of the `powershell` provider.
    See TESTING.md. On a node enrolled with a non-default environment, pass
    -Environment. The apply must run as SYSTEM (Scheduled Task): the SSH
    channel cannot host the `powershell` provider's stdin.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Site,

    [Parameter(Mandatory)]
    [string] $Modulepath,

    [string] $RepoDir = 'C:\wps-repo',

    [string] $Environment = '',

    # Issue #112 review (HIGH): the bracketed fixture publish path
    # (Publish-Module with bracketed filenames, New-ModuleManifest
    # -RootModule 'Bracket[Beta].psm1') has zero Windows evidence yet.
    # Keep it out of the per-PR gate: only -IncludeBrackets runs publish,
    # seed and assert the Bracket[Beta] resource. Per-PR applies the
    # brackets-free catalogue (WpsRepoTest only) and stays green while the
    # wildcard path is proven on the weekly schedule.
    [switch] $IncludeBrackets
)

$ErrorActionPreference = 'Stop'

$Site = (Resolve-Path -LiteralPath $Site).ProviderPath
$failed = 0

function Assert-True([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $script:failed++ }
}

function Invoke-PuppetApply([string] $Label) {
    Write-Host "--- $Label : puppet apply $Site"
    $envArgs = @()
    if ($Environment -ne '') { $envArgs = @('--environment', $Environment) }
    $output = & puppet apply --detailed-exitcodes @envArgs --modulepath $Modulepath --verbose $Site 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    Write-Host ("exit code: {0}" -f $code)
    $code
}

Write-Host ("Host: Windows PowerShell {0} on {1}" -f $PSVersionTable.PSVersion, (Get-CimInstance Win32_OperatingSystem).Caption)
Write-Host ("Running as: {0}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)

if (-not (Get-Command puppet -ErrorAction SilentlyContinue)) {
    throw 'puppet is not on PATH (install puppet-agent 8 first).'
}

# Build and publish the fixture module. Publish-Module needs -Force when
# the host is non-interactive (Scheduled Task as SYSTEM): without it,
# Install-NuGetClientBinaries throws on ShouldContinue (issue #85).
$srcRoot = Join-Path $env:TEMP 'wpsrepotest\src\WpsRepoTest\1.0.0'
if (Test-Path $srcRoot) { Remove-Item -Recurse -Force $srcRoot }
New-Item -ItemType Directory -Path $srcRoot -Force | Out-Null
Set-Content -LiteralPath (Join-Path $srcRoot 'WpsRepoTest.psm1') -Value "function Get-WpsRepoTest { 'repo-ok' }`n" -Encoding UTF8
New-ModuleManifest -Path (Join-Path $srcRoot 'WpsRepoTest.psd1') `
    -ModuleVersion '1.0.0' -GUID '11111111-2222-3333-4444-555555555555' `
    -Author 'CI' -CompanyName 'CI' -Description 'Issue85 local repository fixture.' `
    -RootModule 'WpsRepoTest.psm1' -FunctionsToExport @('Get-WpsRepoTest')

if (Test-Path -LiteralPath $RepoDir) { Remove-Item -Recurse -Force -LiteralPath $RepoDir }
New-Item -ItemType Directory -Path $RepoDir -Force | Out-Null
try { Unregister-PSRepository -Name WpsLocal -ErrorAction SilentlyContinue } catch {}
Register-PSRepository -Name WpsLocal -SourceLocation $RepoDir -PublishLocation $RepoDir -InstallationPolicy Trusted
Publish-Module -Path $srcRoot -Repository WpsLocal -Force
Write-Host "Published WpsRepoTest 1.0.0 to $RepoDir"
Assert-True ((Find-Module -Name WpsRepoTest -Repository WpsLocal).Version -eq '1.0.0') 'local repo serves WpsRepoTest 1.0.0'

# Issue #112, Gap 2: the Gallery has no bracketed names, so only this local
# repo can prove the wildcard-escaped install path converges for real.
# Scheduled-only until the first Windows green run (see -IncludeBrackets):
# Publish-Module cannot publish a bracketed manifest: it runs
# Test-ModuleManifest internally, which rejects the wildcard RootModule
# 'Bracket[Beta].psm1'. The fixture nupkg is therefore packed by hand with
# the .NET zip API (same layout Publish-Module would emit, OPC parts
# included); the nupkg filename keeps the brackets because the provider keys
# packages on the filename id. The install/apply path under test is unchanged.
if ($IncludeBrackets) {
$bbStage = Join-Path $env:TEMP 'wpsrepotest\src\BracketStage\1.0.0'
if (Test-Path $bbStage) { Remove-Item -Recurse -Force $bbStage }
New-Item -ItemType Directory -Path $bbStage -Force | Out-Null
Set-Content -LiteralPath (Join-Path $bbStage 'Bracket[Beta].psm1') -Value "function Get-BracketBeta { 'bracket' }`n" -Encoding UTF8
New-ModuleManifest -Path (Join-Path $bbStage 'BracketStage.psd1') `
    -ModuleVersion '1.0.0' -GUID '44444444-5555-6666-7777-888888888888' `
    -Author 'CI' -CompanyName 'CI' -Description 'Issue112 bracketed local repository fixture.' `
    -RootModule 'Bracket[Beta].psm1' -FunctionsToExport @('Get-BracketBeta')
[void][System.IO.File]::Move(
    (Join-Path $bbStage 'BracketStage.psd1'),
    (Join-Path $bbStage 'Bracket[Beta].psd1'))
$bbNuspec = Join-Path $bbStage 'BracketStage.nuspec'
Set-Content -LiteralPath $bbNuspec -Value @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>Bracket[Beta]</id>
    <version>1.0.0</version>
    <authors>CI</authors>
    <owners>CI</owners>
    <description>Issue #112 bracketed local repository fixture.</description>
    <tags>PSModule PSFunction_Get-BracketBeta PSIncludes_Function</tags>
  </metadata>
</package>
"@ -Encoding UTF8
# NuGet readers open the nupkg as an OPC package, so ship the minimal
# package parts alongside the module files. The nuspec filename stays
# bracket-free (only the <id> inside keeps Bracket[Beta]) so the
# relationship target needs no URI escaping.
Set-Content -LiteralPath (Join-Path $bbStage '[Content_Types].xml') -Value @"
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="nuspec" ContentType="application/octet" />
  <Default Extension="psd1" ContentType="application/octet" />
  <Default Extension="psm1" ContentType="application/octet" />
  <Default Extension="rels" ContentType="application/octet" />
</Types>
"@ -Encoding UTF8
$bbRelsDir = Join-Path $bbStage '_rels'
New-Item -ItemType Directory -Path $bbRelsDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $bbRelsDir '.rels') -Value @"
<?xml version="1.0" encoding="utf-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Type="http://schemas.microsoft.com/packaging/2010/07/manifest" Target="/BracketStage.nuspec" Id="rId1" />
</Relationships>
"@ -Encoding UTF8
$bbNupkg = Join-Path $RepoDir 'Bracket[Beta].1.0.0.nupkg'
if (Test-Path -LiteralPath $bbNupkg) { Remove-Item -Force -LiteralPath $bbNupkg }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($bbStage, $bbNupkg)
Write-Host "Published Bracket[Beta] 1.0.0 to $RepoDir (nupkg filename carries the brackets: the provider keys packages on filename id)"
Assert-True ((Find-Module -Name 'Bracket`[Beta`]' -Repository WpsLocal).Version -eq '1.0.0') 'local repo serves Bracket[Beta] 1.0.0'
}

# Start clean so the first apply really installs.
try { Uninstall-Module -Name WpsRepoTest -AllVersions -Force -ErrorAction SilentlyContinue } catch {}
if ($IncludeBrackets) {
try { Uninstall-Module -Name 'Bracket`[Beta`]' -AllVersions -Force -ErrorAction SilentlyContinue } catch {}
}

# Issue #106: an interrupted install leaves an empty version folder behind,
# which used to satisfy the install check forever. Seed one so the first
# apply must reinstall it (exit 2); the second apply must then be clean
# (exit 0). Whether Install-Module -Force repairs the seeded folder in place
# is exactly what this run proves.
$seedParent = 'C:\Program Files\WindowsPowerShell\Modules\WpsRepoTest'
try { if (Test-Path -LiteralPath $seedParent) { Remove-Item -Recurse -Force -LiteralPath $seedParent } } catch {}
New-Item -ItemType Directory -Path (Join-Path $seedParent '1.0.0') -Force | Out-Null

# Same interrupted-install seed for the bracketed module (scheduled only):
# New-Item has no -LiteralPath on 5.1, so the .NET API creates the bracketed tree.
if ($IncludeBrackets) {
$bbSeedParent = 'C:\Program Files\WindowsPowerShell\Modules\Bracket[Beta]'
try { if (Test-Path -LiteralPath $bbSeedParent) { Remove-Item -Recurse -Force -LiteralPath $bbSeedParent } } catch {}
[void][System.IO.Directory]::CreateDirectory((Join-Path $bbSeedParent '1.0.0'))
}

$first = Invoke-PuppetApply 'first run'
Assert-True (($first -band 1) -eq 0) ("first run succeeded (exit $first)")
Assert-True ($first -eq 2) ("first run reinstalled the seeded empty folder (exit $first, expected 2)")

$second = Invoke-PuppetApply 'second run'
Assert-True (($second -band 1) -eq 0) ("second run succeeded (exit $second)")
Assert-True ($second -eq 0) ("second run changed nothing (exit $second, expected 0)")

try {
    $installed = Get-InstalledModule -Name WpsRepoTest -AllVersions -ErrorAction Stop
    Assert-True (($installed.Version -join ',') -eq '1.0.0') 'repository: pinned 1.0.0 installed'
    $modDir = 'C:\Program Files\WindowsPowerShell\Modules\WpsRepoTest\1.0.0'
    Assert-True (Test-Path -LiteralPath (Join-Path $modDir 'WpsRepoTest.psm1')) 'repository: module files under AllUsers scope'
    Import-Module WpsRepoTest -Force -ErrorAction Stop
    Assert-True ((Get-WpsRepoTest) -eq 'repo-ok') 'repository: imported module runs'
    Remove-Module WpsRepoTest -Force -ErrorAction SilentlyContinue

    if ($IncludeBrackets) {
    # -Name is a wildcard: escape the brackets with a backtick (same escaping
    # the generated scripts use, issue #73). -FullyQualifiedName takes the
    # literal name for the import.
    $bbInstalled = Get-InstalledModule -Name 'Bracket`[Beta`]' -AllVersions -ErrorAction Stop
    Assert-True (($bbInstalled.Version -join ',') -eq '1.0.0') 'repository: pinned bracketed 1.0.0 installed'
    $bbDir = 'C:\Program Files\WindowsPowerShell\Modules\Bracket[Beta]\1.0.0'
    Assert-True (Test-Path -LiteralPath (Join-Path $bbDir 'Bracket[Beta].psm1')) 'repository: bracketed module files under AllUsers scope'
    Import-Module -FullyQualifiedName @{ ModuleName = 'Bracket[Beta]'; ModuleVersion = '1.0.0' } -Force -ErrorAction Stop
    Assert-True ((Get-BracketBeta) -eq 'bracket') 'repository: bracketed module imports and runs'
    Remove-Module -Name 'Bracket`[Beta`]' -Force -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Host ("FAIL exception: {0}" -f $_)
    $script:failed++
}

# Issue #112, Gap 5: the empty seeds above prove the classic interrupted
# shape; a mid-Save-Module state can also leave files without a manifest, so
# prove that shape reinstalls for real too. The corrupt-manifest branch shares
# the same guard outcome (Test-ModuleHealthy $false -> reinstall) and stays
# covered by the offline replay in Test-WindowsRuntime.ps1 (see TESTING.md).
$repoModDir = 'C:\Program Files\WindowsPowerShell\Modules\WpsRepoTest\1.0.0'
$repoManifest = Join-Path $repoModDir 'WpsRepoTest.psd1'
if (Test-Path -LiteralPath $repoManifest) {
Remove-Item -Force -LiteralPath $repoManifest
} else {
Write-Host 'WARNING third run skipped: manifest already missing (converge failed?) — continuing to fourth run and cleanup'
}
$third = Invoke-PuppetApply 'third run (partial install without a manifest)'
Assert-True (($third -band 1) -eq 0) ("third run succeeded (exit $third)")
Assert-True ($third -eq 2) ("third run reinstalled the partial folder (exit $third, expected 2)")

$fourth = Invoke-PuppetApply 'fourth run'
Assert-True (($fourth -band 1) -eq 0) ("fourth run succeeded (exit $fourth)")
Assert-True ($fourth -eq 0) ("fourth run changed nothing (exit $fourth, expected 0)")
Assert-True (Test-Path -LiteralPath (Join-Path $repoModDir 'WpsRepoTest.psd1')) 'repository: manifest restored after the partial reinstall'

# Leave the node as found: uninstall what the catalogue installed, drop the
# test repository registration and remove the staging trees. The converged
# state was already asserted above.
try { Uninstall-Module -Name WpsRepoTest -AllVersions -Force -ErrorAction SilentlyContinue } catch {}
if ($IncludeBrackets) {
try { Uninstall-Module -Name 'Bracket`[Beta`]' -AllVersions -Force -ErrorAction SilentlyContinue } catch {}
}
try { Unregister-PSRepository -Name WpsLocal -ErrorAction SilentlyContinue } catch {}
try { if (Test-Path -LiteralPath $RepoDir) { Remove-Item -Recurse -Force -LiteralPath $RepoDir } } catch {}
try { $srcParent = Join-Path $env:TEMP 'wpsrepotest'; if (Test-Path -LiteralPath $srcParent) { Remove-Item -Recurse -Force -LiteralPath $srcParent } } catch {}

if ($failed -gt 0) { Write-Host "FAILED: $failed check(s)"; exit 1 }
Write-Host 'OK'
