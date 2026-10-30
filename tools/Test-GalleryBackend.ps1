<#
.SYNOPSIS
    Validates the repository backend against the real PowerShell Gallery.

.DESCRIPTION
    Scheduled Gallery end-to-end test (issue #112, Gap 1): the only run
    allowed to reach the real Gallery, so per-PR jobs stay offline. Applies
    spec/integration/site_gallery.pp twice with `puppet apply
    --detailed-exitcodes` as SYSTEM (Scheduled Task): the first run installs
    the pinned PSScriptAnalyzer 1.21.0 from PSGallery (exit 2); the second
    must change nothing (exit 0). Functional checks then verify the converged
    state: Get-InstalledModule, the AllUsers layout and an Import-Module
    round-trip. The pinned version is uninstalled first (start clean, so the
    first run really installs) and again at the end (leave the node as found).

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

    [string] $ModuleName = 'PSScriptAnalyzer',

    [string] $ModuleVersion = '1.21.0',

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
    # Puppet failures are data, not script bugs: a failing catalogue writes
    # to stderr, which would throw NativeCommandError under 'Stop' before the
    # exit code is even read. Relax the preference for the call only, so the
    # exit code decides the asserts below.
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & puppet apply --detailed-exitcodes @envArgs --modulepath $Modulepath --verbose $Site 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $oldEAP
    $output | ForEach-Object { Write-Host $_ }
    Write-Host ("exit code: {0}" -f $code)
    $code
}

Write-Host ("Host: Windows PowerShell {0} on {1}" -f $PSVersionTable.PSVersion, (Get-CimInstance Win32_OperatingSystem).Caption)
Write-Host ("Running as: {0}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)

if (-not (Get-Command puppet -ErrorAction SilentlyContinue)) {
    throw 'puppet is not on PATH (install puppet-agent 8 first).'
}

# PSGallery is registered by default, but a hardened node may have removed
# it: restore the default registration rather than failing the run.
if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Write-Host 'PSGallery not registered, restoring the default registration.'
    Register-PSRepository -Default
}

# Start clean so the first apply really installs. Only the pinned version is
# removed: a lab node may carry other versions we must not touch.
try { Uninstall-Module -Name $ModuleName -RequiredVersion $ModuleVersion -Force -ErrorAction SilentlyContinue } catch {}

$first = Invoke-PuppetApply 'first run'
Assert-True (($first -band 1) -eq 0) ("first run succeeded (exit $first)")
Assert-True ($first -eq 2) ("first run installed the Gallery module (exit $first, expected 2)")

$second = Invoke-PuppetApply 'second run'
Assert-True (($second -band 1) -eq 0) ("second run succeeded (exit $second)")
Assert-True ($second -eq 0) ("second run changed nothing (exit $second, expected 0)")

try {
    $installed = Get-InstalledModule -Name $ModuleName -RequiredVersion $ModuleVersion -ErrorAction Stop
    Assert-True ($installed.Version -eq $ModuleVersion) ("gallery: pinned $ModuleVersion installed")
    $modDir = "C:\Program Files\WindowsPowerShell\Modules\$ModuleName\$ModuleVersion"
    Assert-True (Test-Path -LiteralPath (Join-Path $modDir "$ModuleName.psd1")) 'gallery: module files under AllUsers scope'
    Import-Module $ModuleName -RequiredVersion $ModuleVersion -Force -ErrorAction Stop
    Assert-True ($null -ne (Get-Module -Name $ModuleName)) 'gallery: imported module runs'
    Remove-Module $ModuleName -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Host ("FAIL exception: {0}" -f $_)
    $script:failed++
}

# Leave the node as found: only the pinned version this run installed.
try { Uninstall-Module -Name $ModuleName -RequiredVersion $ModuleVersion -Force -ErrorAction SilentlyContinue } catch {}

if ($failed -gt 0) { Write-Host "FAILED: $failed check(s)"; exit 1 }
Write-Host 'OK'
