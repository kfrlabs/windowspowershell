<#
.SYNOPSIS
    Installs PSScriptAnalyzer reliably on CI runners.

.DESCRIPTION
    `Install-Module PSScriptAnalyzer -Scope CurrentUser -Force` alone is flaky
    on fresh GitHub runners (ubuntu + windows-2022/2025): the PSGallery
    repository is sometimes unregistered, untrusted, or unreachable on the
    first hit, failing with "No match was found for the specified search
    criteria and module name 'PSScriptAnalyzer'".

    This helper makes the bootstrap explicit and retries the install:
    TLS 1.2, NuGet provider, Register-PSRepository -Default when PSGallery is
    missing, trusted policy, then Install-Module with retries.

    Works under Windows PowerShell 5.1 and PowerShell 7. Offline rendering and
    runtime smoke tests never need the Gallery; only the lint leg calls this.
#>
[CmdletBinding()]
param(
    [string] $Name = 'PSScriptAnalyzer',

    [int] $Retries = 3
)

$ErrorActionPreference = 'Stop'

# PSGallery requires TLS 1.2; harmless on hosts where it is already default.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    Write-Host "note: could not set TLS 1.2: $_"
}

# NuGet provider is required by Install-Module on 5.1 and on fresh 7.x images.
try {
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $nuget -or ([version]$nuget.Version -lt [version]'2.8.5.201')) {
        Write-Host 'Installing NuGet package provider...'
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }
} catch {
    Write-Host "note: NuGet provider bootstrap: $_"
}

if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Write-Host 'PSGallery not registered, registering default...'
    Register-PSRepository -Default -ErrorAction Stop
}

try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
} catch {
    Write-Host "note: could not trust PSGallery: $_"
}

Get-PSRepository -Name PSGallery | Format-Table Name, SourceLocation, InstallationPolicy | Out-String | Write-Host

$attempt = 0
while ($true) {
    $attempt++
    try {
        if (Get-Module -ListAvailable -Name $Name) {
            Write-Host ("{0} already available: {1}" -f $Name, ((Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1).Version))
        } else {
            Write-Host ("Installing {0} (attempt {1}/{2})..." -f $Name, $attempt, $Retries)
            Install-Module -Name $Name -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        }
        Import-Module $Name -ErrorAction Stop
        Write-Host ("{0} {1}" -f $Name, (Get-Module $Name).Version)
        break
    } catch {
        Write-Host ("attempt {0} failed: {1}" -f $attempt, $_.Exception.Message)
        if ($attempt -ge $Retries) { throw }
        Start-Sleep -Seconds (5 * $attempt)
    }
}
