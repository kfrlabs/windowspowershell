<#
.SYNOPSIS
    Proves the manage_profiles rollback leaves profile files on disk.

.DESCRIPTION
    Profiles upgrade coverage (issue #129, R6): applies the managed
    catalogue (spec/integration/site_profiles_managed.pp, with
    manage_profiles => true) twice, snapshots the SHA-256 of each managed
    profile file, then applies the implicit catalogue
    (spec/integration/site_profiles_implicit.pp, without manage_profiles)
    twice. The implicit runs must change nothing (exit 0 both), the hashes
    must be byte-identical, and the old Import-Module line must still be
    present, proving the files were left on disk rather than rebuilt.

    Everything is offline: the WpsProfTest module declares no scripts (an
    empty Functions/ is a supported no-op), so no Gallery or NuGet access
    is needed. Run from Windows PowerShell 5.1, the host of the `powershell`
    provider. See TESTING.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ManagedSite,

    [Parameter(Mandatory)]
    [string] $ImplicitSite,

    [Parameter(Mandatory)]
    [string] $Modulepath,

    [string] $ModuleRoot = 'C:\wps-int\Modules',

    # Hosts whose puppet.conf pins a non-existent default environment need
    # an explicit override (see Test-PuppetApply.ps1). Leave empty on a
    # fresh host (CI runners), where `production` just works.
    [string] $Environment = ''
)

$ErrorActionPreference = 'Stop'

$ManagedSite = (Resolve-Path -LiteralPath $ManagedSite).ProviderPath
$ImplicitSite = (Resolve-Path -LiteralPath $ImplicitSite).ProviderPath
$failed = 0

function Assert-True([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $script:failed++ }
}

# `puppet apply --detailed-exitcodes`: 0 = no changes, 2 = changes applied,
# any bit 1 set (1, 3, 5, ...) = failure. Returns the raw exit code.
# The site travels as an explicit parameter: phase A and phase B apply
# different catalogues through the same helper. Native command output is
# captured in a local and replayed so it never leaks into the return value
# (see Test-PuppetApply.ps1).
function Invoke-PuppetApply([string] $Label, [string] $ApplySite) {
    Write-Host "--- $Label : puppet apply $ApplySite"
    $envArgs = @()
    if ($Environment -ne '') { $envArgs = @('--environment', $Environment) }
    # Puppet failures are data, not script bugs: relax the preference for
    # the call only, so the exit code decides the asserts below.
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & puppet apply --detailed-exitcodes @envArgs --modulepath $Modulepath --verbose $ApplySite 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $oldEAP
    $output | ForEach-Object { Write-Host $_ }
    Write-Host ("exit code: {0}" -f $code)
    $code
}

Write-Host ("Host: Windows PowerShell {0} on {1}" -f $PSVersionTable.PSVersion, (Get-CimInstance Win32_OperatingSystem).Caption)

if (-not (Get-Command puppet -ErrorAction SilentlyContinue)) {
    throw 'puppet is not on PATH (install puppet-agent 8 first).'
}

try {
    # Phase A: managed profiles converge, then stay clean.
    $first = Invoke-PuppetApply 'managed first run' $ManagedSite
    Assert-True (($first -band 1) -eq 0) ("managed first run succeeded (exit $first)")
    Assert-True ($first -eq 2) ("managed first run converged (exit $first, expected 2)")

    $second = Invoke-PuppetApply 'managed second run' $ManagedSite
    Assert-True (($second -band 1) -eq 0) ("managed second run succeeded (exit $second)")
    Assert-True ($second -eq 0) ("managed second run changed nothing (exit $second, expected 0)")

    # Snapshot the managed profile files that exist. Both site files pin
    # manage_pwsh_profile => false, so only the two Windows PowerShell
    # profiles are ever managed here, on every host.
    $profilePaths = @(
        'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1',
        'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1'
    )
    $hashes = @{}
    foreach ($profilePath in $profilePaths) {
        if (Test-Path -LiteralPath $profilePath) {
            $hashes[$profilePath] = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
            Write-Host ("snapshot {0} : {1}" -f $profilePath, $hashes[$profilePath])
        } else {
            Write-Host ("snapshot {0} : missing, skipped" -f $profilePath)
        }
    }
    Assert-True ($hashes.Count -gt 0) 'managed: at least one profile file written'

    # Phase B: the implicit default (manage_profiles omitted, so false)
    # declares no profile resources. Both runs must be clean, the hashes
    # byte-identical, and the old Import-Module line still present: the
    # files were left on disk, not rebuilt.
    $third = Invoke-PuppetApply 'implicit first run' $ImplicitSite
    Assert-True (($third -band 1) -eq 0) ("implicit first run succeeded (exit $third)")
    Assert-True ($third -eq 0) ("implicit first run changed nothing (exit $third, expected 0)")

    $fourth = Invoke-PuppetApply 'implicit second run' $ImplicitSite
    Assert-True (($fourth -band 1) -eq 0) ("implicit second run succeeded (exit $fourth)")
    Assert-True ($fourth -eq 0) ("implicit second run changed nothing (exit $fourth, expected 0)")

    foreach ($profilePath in @($hashes.Keys)) {
        Assert-True (Test-Path -LiteralPath $profilePath) ("implicit: profile still on disk ($profilePath)")
        $now = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
        Assert-True ($now -ceq $hashes[$profilePath]) ("implicit: profile byte-identical ($profilePath)")
        $profileText = [System.IO.File]::ReadAllText($profilePath)
        Assert-True ($profileText -match 'WpsProfTest\.psd1') ("implicit: WpsProfTest import line still present ($profilePath)")
    }
}
finally {
    # No repository was ever registered (no repo used), so there is nothing
    # to unregister. Remove the test module tree to leave a clean node.
    $testTree = Join-Path $ModuleRoot 'WpsProfTest'
    if (Test-Path -LiteralPath $testTree) { Remove-Item -Recurse -Force -LiteralPath $testTree }
}

if ($failed -gt 0) { Write-Host "FAILED: $failed check(s)"; exit 1 }
Write-Host 'OK'
