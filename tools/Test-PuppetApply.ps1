<#
.SYNOPSIS
    Applies the integration catalog twice and checks the second run is clean.

.DESCRIPTION
    Real-agent counterpart of the offline Test-WindowsRuntime.ps1 replay: runs
    `puppet apply` on spec/integration/site.pp (in-house module by bulk copy,
    one script by content, one external module by file copy, one profile
    import), then applies the same catalog again. The first run may change
    resources (exit code 2 with --detailed-exitcodes); the second must change
    nothing (exit code 0). Functional checks then verify the converged state:
    manifest version and exports, Import-Module round-trip of both modules,
    and the profile import line.

    Everything is offline: the catalog only uses the `source` backend served
    from the wps_integration fixture module, so no Gallery or NuGet access is
    needed. Run from Windows PowerShell 5.1, the host of the `powershell`
    provider. See TESTING.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Site,

    [Parameter(Mandatory)]
    [string] $Modulepath,

    [string] $ModuleRoot = 'C:\wps-int\Modules',

    # Hosts whose puppet.conf pins a non-existent default environment (e.g. an
    # agent enrolled with environment=saim) need an explicit override, or every
    # `puppet` invocation fails before it starts. Leave empty on a fresh host
    # (CI runners), where the default `production` environment just works.
    [string] $Environment = ''
)

$ErrorActionPreference = 'Stop'

$Site = (Resolve-Path -LiteralPath $Site).ProviderPath
$failed = 0

function Assert-True([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $script:failed++ }
}

# `puppet apply --detailed-exitcodes`: 0 = no changes, 2 = changes applied,
# any bit 1 set (1, 3, 5, ...) = failure. Returns the raw exit code.
function Invoke-PuppetApply([string] $Label) {
    Write-Host "--- $Label : puppet apply $Site"
    $envArgs = @()
    if ($Environment -ne '') { $envArgs = @('--environment', $Environment) }
    & puppet apply --detailed-exitcodes @envArgs --modulepath $Modulepath --verbose $Site
    $code = $LASTEXITCODE
    Write-Host ("exit code: {0}" -f $code)
    $code
}

Write-Host ("Host: Windows PowerShell {0} on {1}" -f $PSVersionTable.PSVersion, (Get-CimInstance Win32_OperatingSystem).Caption)

if (-not (Get-Command puppet -ErrorAction SilentlyContinue)) {
    throw 'puppet is not on PATH (install puppet-agent 8 first).'
}

$first = Invoke-PuppetApply 'first run'
Assert-True (($first -band 1) -eq 0) ("first run succeeded (exit $first)")
Assert-True (($first -eq 0) -or ($first -eq 2)) ("first run exit is 0 or 2 (got $first)")

$second = Invoke-PuppetApply 'second run'
Assert-True (($second -band 1) -eq 0) ("second run succeeded (exit $second)")
Assert-True ($second -eq 0) ("second run changed nothing (exit $second, expected 0)")

# Converged state, checked the way a user would see it.
try {
    $manifest = Join-Path $ModuleRoot 'WpsInt\1.0\WpsInt.psd1'
    Assert-True (Test-Path -LiteralPath $manifest) 'in-house: manifest written'
    $data = Import-PowerShellDataFile -LiteralPath $manifest
    Assert-True ($data.ModuleVersion -eq '1.0') 'in-house: manifest version is 1.0'
    Assert-True ((@($data.NestedModules) -contains 'Functions\Get-WpsIntHello.ps1') -and ((@($data.NestedModules) -join ',') -match 'Get-WpsIntFromSource')) 'in-house: both scripts are nested modules'

    $witness = Join-Path $ModuleRoot 'WpsInt\1.0\.manifest-params'
    Assert-True (Test-Path -LiteralPath $witness) 'in-house: manifest witness written'

    $env:PSModulePath = "$ModuleRoot;$env:PSModulePath"
    Import-Module WpsInt -Force
    Assert-True ((Get-WpsIntHello) -eq 'hello') 'in-house: content-deployed script runs'
    Assert-True ((Get-WpsIntFromSource) -eq 'from-source') 'in-house: source-deployed script runs'
    Remove-Module WpsInt -Force -ErrorAction SilentlyContinue

    $copied = Join-Path $ModuleRoot 'WpsIntCopied\1.2.3\WpsIntCopied.psm1'
    Assert-True (Test-Path -LiteralPath $copied) 'external: file-copy backend deployed the pinned version'
    Import-Module WpsIntCopied -Force
    Assert-True ((Get-WpsIntCopied) -eq 'copied') 'external: copied module imports and runs'
    Remove-Module WpsIntCopied -Force -ErrorAction SilentlyContinue

    $profilePath = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
    Assert-True (Test-Path -LiteralPath $profilePath) 'profile: machine-wide profile written'
    $profileText = [System.IO.File]::ReadAllText($profilePath)
    Assert-True ($profileText -match "WpsInt\.psd1") 'profile: WpsInt import line present'
}
catch {
    Write-Host ("FAIL exception: {0}" -f $_)
    $script:failed++
}

if ($failed -gt 0) { Write-Host "FAILED: $failed check(s)"; exit 1 }
Write-Host 'OK'
