<#
.SYNOPSIS
    Validates the repository backend against a local file repository.

.DESCRIPTION
    Offline counterpart of the Gallery path that issue #85 found never
    exercised: registers a local file PSRepository (visible to the account
    running this script — run it as SYSTEM, the Puppet agent account, via a
    Scheduled Task: Register-PSRepository is per-user and a repository
    registered interactively is invisible to the agent), publishes a minimal
    WpsRepoTest 1.0.0 module into it, then applies
    spec/integration/site_repository.pp twice with `puppet apply
    --detailed-exitcodes`. The first run may change resources (exit 2); the
    second must change nothing (exit 0). Functional checks then verify the
    converged state: Get-InstalledModule, directory layout, Import-Module
    round-trip.

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

    [string] $Environment = ''
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

# Start clean so the first apply really installs.
try { Uninstall-Module -Name WpsRepoTest -AllVersions -Force -ErrorAction SilentlyContinue } catch {}

# Issue #106: an interrupted install leaves an empty version folder behind,
# which used to satisfy the install check forever. Seed one so the first
# apply must reinstall it (exit 2); the second apply must then be clean
# (exit 0). Whether Install-Module -Force repairs the seeded folder in place
# is exactly what this run proves.
$seedParent = 'C:\Program Files\WindowsPowerShell\Modules\WpsRepoTest'
try { if (Test-Path -LiteralPath $seedParent) { Remove-Item -Recurse -Force -LiteralPath $seedParent } } catch {}
New-Item -ItemType Directory -Path (Join-Path $seedParent '1.0.0') -Force | Out-Null

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
}
catch {
    Write-Host ("FAIL exception: {0}" -f $_)
    $script:failed++
}

if ($failed -gt 0) { Write-Host "FAILED: $failed check(s)"; exit 1 }
Write-Host 'OK'
