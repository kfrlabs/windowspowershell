<#
.SYNOPSIS
    Checks that the OS gate of templates/pwsh_profile.ps1.epp is reliable here.

.DESCRIPTION
    The managed PowerShell 7 profile only configures PSReadLine when
    [System.Environment]::OSVersion.Version.Major -ge 10. A host process without
    a Windows 10 compatibility manifest is told it runs on Windows 8 (6.2), so
    the gate could skip the configuration silently. This script compares the
    value the gate sees with the real version reported by CIM, and fails when
    the gate would give a different answer.

    Run it with PowerShell 7 (the only host that loads the profile) on every
    supported Windows release; it also works under Windows PowerShell 5.1.
    See TESTING.md.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$seen = [System.Environment]::OSVersion.Version
$real = [version] (Get-CimInstance -ClassName Win32_OperatingSystem).Version
$gate = $seen.Major -ge 10
$expected = $real.Major -ge 10

Write-Host ("Host: PowerShell {0} ({1}); OSVersion={2}; CIM={3}; gate={4}; expected={5}" -f
    $PSVersionTable.PSVersion, $PSVersionTable.PSEdition, $seen, $real, $gate, $expected)

if ($gate -ne $expected) {
    Write-Host 'FAILED: the gate does not match the real Windows version on this host.'
    exit 1
}
Write-Host 'OK'
