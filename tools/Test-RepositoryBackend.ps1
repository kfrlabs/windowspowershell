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
$bbNuspec = Join-Path $bbStage 'Bracket[Beta].nuspec'
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
# package parts alongside the module files. The nuspec entry keeps the
# bracketed name to match the package id (readers look up <id>.nuspec);
# entry names inside the zip are literal, so no wildcard is involved.
# The nupkg filename keeps the brackets too: the provider keys packages on
# the filename id.
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
  <Relationship Type="http://schemas.microsoft.com/packaging/2010/07/manifest" Target="/Bracket[Beta].nuspec" Id="rId1" />
</Relationships>
"@ -Encoding UTF8
$bbNupkg = Join-Path $RepoDir 'Bracket[Beta].1.0.0.nupkg'
if (Test-Path -LiteralPath $bbNupkg) { Remove-Item -Force -LiteralPath $bbNupkg }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($bbStage, $bbNupkg)
# Diagnostics stay in the log: entry names of the hand-packed nupkg next to
# the Publish-Module one, plus the unfiltered provider view of the repo.
Write-Host "--- repo files:"; Get-ChildItem -LiteralPath $RepoDir | ForEach-Object { Write-Host ("repo file: {0}" -f $_.Name) }
$bbZip = [System.IO.Compression.ZipFile]::OpenRead($bbNupkg)
$bbZip.Entries | ForEach-Object { Write-Host ("bracketed nupkg entry: {0}" -f $_.FullName) }
$bbZip.Dispose()
$goodNupkg = Join-Path $RepoDir 'WpsRepoTest.1.0.0.nupkg'
$goodZip = [System.IO.Compression.ZipFile]::OpenRead($goodNupkg)
$goodZip.Entries | ForEach-Object { Write-Host ("reference nupkg entry: {0}" -f $_.FullName) }
$goodZip.Dispose()
Find-Package -Source WpsLocal | ForEach-Object { Write-Host ("repo package: {0} {1}" -f $_.Name, $_.Version) }
Write-Host "Published Bracket[Beta] 1.0.0 to $RepoDir (nupkg filename carries the brackets: the provider keys packages on filename id)"
# Find-Module -Name cannot match bracketed names (its PackageManagement name
# matcher does not honor the backtick escaping that Install-Module and friends
# accept, issue #132): assert via a wildcard-free enumeration instead. The
# install/apply path under test is unchanged.
$bbFound = Find-Package -Source WpsLocal | Where-Object { $_.Name -eq 'Bracket[Beta]' }
Assert-True (($null -ne $bbFound) -and ($bbFound.Version -eq '1.0.0')) 'local repo serves Bracket[Beta] 1.0.0'
}

# Start clean so the first apply really installs.
try { Uninstall-Module -Name WpsRepoTest -AllVersions -Force -ErrorAction SilentlyContinue } catch {}
if ($IncludeBrackets) {
try { Uninstall-Module -Name 'Bracket[Beta]' -AllVersions -Force -ErrorAction SilentlyContinue } catch {}
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

# Gap-2 diagnostics (issue #132): the bracketed resource reinstalls every run
# while the plain one converges. Evaluate each install-check link literally
# so the log shows which one fails for bracketed names. Bracket-only: the
# per-PR job has no bracketed fixture, so this block must not run there.
if ($IncludeBrackets) {
$bbDbgDir = 'C:\Program Files\WindowsPowerShell\Modules\Bracket[Beta]'
Write-Host ("dbg bracket dir exists: {0}" -f (Test-Path -LiteralPath $bbDbgDir))
Get-ChildItem -LiteralPath $bbDbgDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("dbg bracket child: {0}" -f $_.Name) }
$bbDbgPsd1 = Join-Path (Join-Path $bbDbgDir '1.0.0') 'Bracket[Beta].psd1'
Write-Host ("dbg bracket psd1 exists: {0}" -f (Test-Path -LiteralPath $bbDbgPsd1))
# Full installed tree via .NET (no wildcard layer at all): shows whether
# Install-Module laid down the psd1/psm1 or left the seeded dir behind.
[System.IO.Directory]::EnumerateFileSystemEntries($bbDbgDir, '*', [System.IO.SearchOption]::AllDirectories) | ForEach-Object { Write-Host ("dbg bracket tree: {0}" -f $_) }
# Save-Module probe: Install-Module reports success but lays down no files.
# Save-Module exercises the same provider download+extract machinery without
# touching AllUsers, showing whether the failure is in the provider download
# or in the AllUsers install step.
$bbSaveDir = Join-Path $env:TEMP 'wpsrepotest\saveprobe'
if (Test-Path -LiteralPath $bbSaveDir) { Remove-Item -Recurse -Force -LiteralPath $bbSaveDir }
New-Item -ItemType Directory -Path $bbSaveDir -Force | Out-Null
try {
    Save-Module -Name 'Bracket`[Beta`]' -RequiredVersion '1.0.0' -Repository WpsLocal -Path $bbSaveDir -Force
    Get-ChildItem -LiteralPath $bbSaveDir -Recurse | ForEach-Object { Write-Host ("dbg saveprobe: {0}" -f $_.FullName) }
} catch {
    Write-Host ("dbg saveprobe FAILED: {0}" -f $_)
}
# Name-matcher matrix (read-only): Find-Package enumeration sees the package,
# but every -Name lookup fails. Try raw, escaped and wildcard spellings to
# learn which matcher PackageManagement actually applies to bracketed ids.
foreach ($bbProbeName in @('Bracket[Beta]', 'Bracket`[Beta`]', 'Bracket*')) {
    try {
        $bbProbeFound = Find-Module -Name $bbProbeName -Repository WpsLocal -ErrorAction Stop
        Write-Host ("dbg findmodule [{0}]: FOUND {1} {2}" -f $bbProbeName, $bbProbeFound.Name, $bbProbeFound.Version)
    } catch {
        Write-Host ("dbg findmodule [{0}]: NoMatch" -f $bbProbeName)
    }
}
# Raw-name Install-Module diagnostic: the matrix above shows the escaped name
# never matches while the raw name does. Install-Module with the escaped name
# exits 0 but lays down no files, so install the bracketed module by its raw
# name and list the tree right away.
try {
    $bbInstallOut = Install-Module -Name 'Bracket[Beta]' -RequiredVersion '1.0.0' -Repository WpsLocal -Scope AllUsers -Force -AllowClobber -Verbose 4>&1
    $bbInstallOut | ForEach-Object { Write-Host ("dbg installraw: {0}" -f $_) }
    Write-Host "dbg installraw: exit ok"
    Get-ChildItem -LiteralPath $bbDbgDir -Recurse | ForEach-Object { Write-Host ("dbg installraw tree: {0}" -f $_.FullName) }
} catch {
    Write-Host ("dbg installraw FAILED: {0}" -f $_)
}
# Where did anything Bracket-related land? The install exits 0 but the seeded
# tree stays empty, so look for mangled directory names elsewhere under the
# AllUsers root (read-only; the '*racket*' pattern itself has no brackets).
Get-ChildItem -LiteralPath 'C:\Program Files\WindowsPowerShell\Modules' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*racket*' } | ForEach-Object { Write-Host ("dbg bracket dirs: {0}" -f $_.FullName) }
} # end if ($IncludeBrackets): bracket-only diagnostics

try {
    $installed = Get-InstalledModule -Name WpsRepoTest -AllVersions -ErrorAction Stop
    Assert-True (($installed.Version -join ',') -eq '1.0.0') 'repository: pinned 1.0.0 installed'
    $modDir = 'C:\Program Files\WindowsPowerShell\Modules\WpsRepoTest\1.0.0'
    Assert-True (Test-Path -LiteralPath (Join-Path $modDir 'WpsRepoTest.psm1')) 'repository: module files under AllUsers scope'
    Import-Module WpsRepoTest -Force -ErrorAction Stop
    Assert-True ((Get-WpsRepoTest) -eq 'repo-ok') 'repository: imported module runs'
    Remove-Module WpsRepoTest -Force -ErrorAction SilentlyContinue

    if ($IncludeBrackets) {
    # PackageManagement compares -Name literally (no backtick unescaping):
    # the escaped spelling never matches while the raw name does (see the
    # dbg findmodule matrix above). Remove-Module is session-local and
    # PowerShell-native, so it keeps the backtick escaping.
    $bbInstalled = Get-InstalledModule -Name 'Bracket[Beta]' -AllVersions -ErrorAction Stop
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
try { Uninstall-Module -Name 'Bracket[Beta]' -AllVersions -Force -ErrorAction SilentlyContinue } catch {}
}
try { Unregister-PSRepository -Name WpsLocal -ErrorAction SilentlyContinue } catch {}
try { if (Test-Path -LiteralPath $RepoDir) { Remove-Item -Recurse -Force -LiteralPath $RepoDir } } catch {}
try { $srcParent = Join-Path $env:TEMP 'wpsrepotest'; if (Test-Path -LiteralPath $srcParent) { Remove-Item -Recurse -Force -LiteralPath $srcParent } } catch {}

if ($failed -gt 0) { Write-Host "FAILED: $failed check(s)"; exit 1 }
Write-Host 'OK'
