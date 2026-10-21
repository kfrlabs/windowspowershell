<#
.SYNOPSIS
    Runs the rendered "runtime" scenario scripts on a real Windows node.

.DESCRIPTION
    Builds a throw-away module tree under C:\wps-ci\Modules (the module_root of
    the `runtime` scenario in spec/unit/rendered_powershell_spec.rb), then
    replays the rendered Exec commands and their unless/onlyif guards the way
    the `powershell` provider does: script text on stdin of Windows PowerShell.
    Everything is offline: no gallery access is needed.

    Run it from Windows PowerShell 5.1 on every supported Windows Server
    release. -RenderedPath points at the `runtime` folder produced with
    WPS_RENDER_DIR. See TESTING.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RenderedPath,

    [string] $Root = 'C:\wps-ci\Modules',

    [string] $RootModule
)

$ErrorActionPreference = 'Stop'

# Not in the param() defaults: $PSScriptRoot is empty there under
# `powershell.exe -File` (Windows PowerShell 5.1).
if (-not $RootModule) {
    $RootModule = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\files\rootmodule.psm1'
}
$RenderedPath = (Resolve-Path -LiteralPath $RenderedPath).ProviderPath
$failed = 0

function Get-RenderedScriptPath([string] $Pattern) {
    $hits = @(Get-ChildItem -LiteralPath $RenderedPath -Filter $Pattern)
    if ($hits.Count -ne 1) { throw "Expected exactly one rendered script for '$Pattern', found $($hits.Count)" }
    $hits[0].FullName
}

# Same contract as the provider: the script is fed to powershell.exe on stdin.
function Invoke-Rendered([string] $Pattern) {
    $path = Get-RenderedScriptPath $Pattern
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 |
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command - | Out-Null
    $LASTEXITCODE
}

function Assert-True([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $script:failed++ }
}

function Assert-Exit([string] $Pattern, [int] $Expected, [string] $Message) {
    $actual = Invoke-Rendered $Pattern
    Assert-True ($actual -eq $Expected) "$Message (exit $actual, expected $Expected)"
}

function New-Dir([string] $Path) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }

Write-Host ("Host: Windows PowerShell {0} on {1}" -f $PSVersionTable.PSVersion, (Get-CimInstance Win32_OperatingSystem).Caption)

if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }

try {
    # In-house module: pinned 1.4, with leftovers next to it.
    $smoke = Join-Path $Root 'WpsSmoke'
    New-Dir (Join-Path $smoke '1.4\Functions\Sub')
    Set-Content -LiteralPath (Join-Path $smoke '1.4\Functions\Get-WpsA.ps1') -Value 'function Get-WpsA { "a" }'
    Set-Content -LiteralPath (Join-Path $smoke '1.4\Functions\Sub\Get-WpsB.ps1') -Value 'function Get-WpsB { "b" }'
    Copy-Item -LiteralPath $RootModule -Destination (Join-Path $smoke '1.4\WpsSmoke.psm1')
    New-Dir (Join-Path $smoke '1.3')
    New-Dir (Join-Path $smoke '1.4.0')
    New-Dir (Join-Path $smoke 'not-a-version')

    Assert-Exit '*purge_other_in-house_versions_of_WpsSmoke_unless*' 1 'in-house: leftover version detected'
    Assert-Exit '*purge_other_in-house_versions_of_WpsSmoke_command*' 0 'in-house: purge runs'
    Assert-Exit '*purge_other_in-house_versions_of_WpsSmoke_unless*' 0 'in-house: purge is idempotent'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $smoke '1.3'))) 'in-house: 1.3 removed'
    Assert-True (Test-Path -LiteralPath (Join-Path $smoke '1.4.0')) 'in-house: 1.4.0 kept (same version as the pin 1.4)'
    Assert-True (Test-Path -LiteralPath (Join-Path $smoke 'not-a-version')) 'in-house: unparseable folder kept'

    foreach ($step in 'create-manifest', 'update-manifest') {
        Assert-Exit "*${step}_WpsSmoke_command*" 0 "manifest: $step runs"
    }
    $psd1 = Join-Path $smoke '1.4\WpsSmoke.psd1'
    Assert-True (Test-Path -LiteralPath $psd1) 'manifest: file written'
    $manifest = Test-ModuleManifest -Path $psd1
    Assert-True ($manifest.Version -eq [version] '1.4') 'manifest: version is 1.4'
    Assert-True (@($manifest.ExportedFunctions.Keys | Sort-Object) -join ',' -eq 'Get-WpsA,Get-WpsB') 'manifest: both functions exported (nested folder included)'
    # Test-ModuleManifest does not resolve .ps1 nested modules, so read the data file.
    $data = Import-PowerShellDataFile -LiteralPath $psd1
    Assert-True ($data.RootModule -eq 'WpsSmoke.psm1') 'manifest: root module declared as RootModule'
    Assert-True ((@($data.NestedModules) -join ',') -eq 'Functions\Get-WpsA.ps1,Functions\Sub\Get-WpsB.ps1') 'manifest: only Functions/ scripts are nested modules'
    Assert-Exit '*unblock-files_WpsSmoke_command*' 0 'unblock-files runs'

    $env:PSModulePath = "$Root;$env:PSModulePath"
    Import-Module WpsSmoke -Force
    Assert-True ((Get-WpsA) -eq 'a' -and (Get-WpsB) -eq 'b') 'module imports and its functions run'
    Remove-Module WpsSmoke -Force

    # External module deployed by copy: only the pinned version may remain.
    $pinned = Join-Path $Root 'WpsPinned'
    foreach ($v in '2.0.0', '2.1.0', '2.10.0') { New-Dir (Join-Path $pinned $v) }
    Assert-Exit '*purge_other_versions_of_WpsPinned_unless*' 1 'pinned: other versions detected'
    Assert-Exit '*purge_other_versions_of_WpsPinned_command*' 0 'pinned: purge runs'
    Assert-Exit '*purge_other_versions_of_WpsPinned_unless*' 0 'pinned: purge is idempotent'
    Assert-True ((@(Get-ChildItem -LiteralPath $pinned -Directory).Name -join ',') -eq '2.1.0') 'pinned: only 2.1.0 left (2.10.0 is not 2.1.0)'

    # ensure => absent.
    $gone = Join-Path $Root 'WpsGone'
    New-Dir (Join-Path $gone '1.0')
    Assert-Exit '*uninstall_WpsGone_unless*' 1 'absent: module still present'
    Assert-Exit '*uninstall_WpsGone_command*' 0 'absent: uninstall runs'
    Assert-Exit '*uninstall_WpsGone_unless*' 0 'absent: uninstall is idempotent'
    Assert-True (-not (Test-Path -LiteralPath $gone)) 'absent: tree removed'
}
finally {
    if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
}

if ($failed -gt 0) { Write-Host "FAILED: $failed check(s)"; exit 1 }
Write-Host 'OK'
