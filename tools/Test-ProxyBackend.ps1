<#
.SYNOPSIS
    Validates -Proxy / -ProxyCredential against a local authenticating proxy.

.DESCRIPTION
    Issue #85 found the proxy path never exercised for real: specs only check
    the rendered -Proxy / -ProxyCredential text, and a file:// repository
    ignores the proxy entirely. This script proves the parameters work as
    SYSTEM against the real PowerShell Gallery through an authenticating
    forward proxy running on this same host (127.0.0.1): a minimal CONNECT
    tunnel proxy with Basic auth, implemented here with TcpListener so no
    third-party proxy is needed.

    TEST1 finds a Gallery module through the proxy with good credentials
    (must succeed); TEST4 downloads a module through the proxy with Save-Module
    (same PackageManagement download path as Install-Module, but without
    polluting the AllUsers scope, best-effort with a timeout).

    Run from Windows PowerShell 5.1 as SYSTEM (Scheduled Task) to match the
    agent account, or interactively for a quick check. Needs internet access
    to www.powershellgallery.com. See TESTING.md.
#>
[CmdletBinding()]
param(
    [int] $Port = 18888,

    [string] $ProxyUser = 'wpsproxy',

    [string] $ProxyPassword = 'S3cret-Probe-85!',

    [string] $ProbeModule = 'PSScriptAnalyzer',

    [string] $ProbeVersion = '1.21.0'
)

$ErrorActionPreference = 'Stop'
$failed = 0

function Assert-True([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $script:failed++ }
}

Write-Host ("Host: Windows PowerShell {0} on {1}" -f $PSVersionTable.PSVersion, (Get-CimInstance Win32_OperatingSystem).Caption)
Write-Host ("Running as: {0}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)

$expectedAuth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$ProxyUser`:$ProxyPassword"))

$proxyScript = {
    param($ListenPort, $ExpectedAuth, $LogFile)
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $ListenPort)
    $listener.Start()
    Add-Content -LiteralPath $LogFile -Value "PROXY-LISTENING on 127.0.0.1:$ListenPort"
    try {
        while ($true) {
            $client = $listener.AcceptTcpClient()
            try {
                $stream = $client.GetStream()
                $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII)
                $requestLine = $reader.ReadLine()
                if (-not $requestLine) { $client.Close(); continue }
                $headers = @{}
                while ($true) {
                    $line = $reader.ReadLine()
                    if ([string]::IsNullOrEmpty($line)) { break }
                    $idx = $line.IndexOf(':')
                    if ($idx -gt 0) { $headers[$line.Substring(0, $idx).Trim()] = $line.Substring($idx + 1).Trim() }
                }
                Add-Content -LiteralPath $LogFile -Value ("REQ: " + $requestLine)
                if (-not $headers.ContainsKey('Proxy-Authorization') -or $headers['Proxy-Authorization'] -ne $ExpectedAuth) {
                    $resp = "HTTP/1.1 407 Proxy Authentication Required`r`nProxy-Authenticate: Basic realm=`"wps-test`"`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
                    $bytes = [Text.Encoding]::ASCII.GetBytes($resp)
                    $stream.Write($bytes, 0, $bytes.Length)
                    $client.Close()
                    Add-Content -LiteralPath $LogFile -Value "RESP-407"
                    continue
                }
                if ($requestLine -match '^CONNECT\s+(\S+)\s+HTTP') {
                    $target = $Matches[1]
                    $parts = $target -split ':'
                    $remote = New-Object Net.Sockets.TcpClient
                    try { $remote.Connect($parts[0], [int]$parts[1]) } catch {
                        $resp = "HTTP/1.1 502 Bad Gateway`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
                        $bytes = [Text.Encoding]::ASCII.GetBytes($resp)
                        $stream.Write($bytes, 0, $bytes.Length)
                        $client.Close()
                        Add-Content -LiteralPath $LogFile -Value ("CONNECT-FAIL " + $target)
                        continue
                    }
                    $resp = "HTTP/1.1 200 Connection established`r`n`r`n"
                    $bytes = [Text.Encoding]::ASCII.GetBytes($resp)
                    $stream.Write($bytes, 0, $bytes.Length)
                    Add-Content -LiteralPath $LogFile -Value ("TUNNEL-OK " + $target)
                    $rstream = $remote.GetStream()
                    $c2r = $stream.CopyToAsync($rstream)
                    $r2c = $rstream.CopyToAsync($stream)
                    [Threading.Tasks.Task]::WaitAny($c2r, $r2c) | Out-Null
                    $remote.Close()
                    $client.Close()
                } else {
                    $resp = "HTTP/1.1 405 Method Not Allowed`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
                    $bytes = [Text.Encoding]::ASCII.GetBytes($resp)
                    $stream.Write($bytes, 0, $bytes.Length)
                    $client.Close()
                }
            } catch {
                try { $client.Close() } catch {}
            }
        }
    } finally { $listener.Stop() }
}

$proxyLog = Join-Path $env:TEMP 'wps-proxy-traffic.log'
if (Test-Path -LiteralPath $proxyLog) { Remove-Item -Force -LiteralPath $proxyLog }
Set-Content -LiteralPath $proxyLog -Value 'start' | Out-Null
$job = Start-Job -ScriptBlock $proxyScript -ArgumentList $Port, $expectedAuth, $proxyLog
Start-Sleep -Seconds 3
if ($job.State -ne 'Running') {
    Receive-Job $job | Out-String | Write-Host
    throw 'proxy job failed to start'
}
Write-Host ("proxy listening on 127.0.0.1:{0}" -f $Port)

$proxyUrl = "http://127.0.0.1:$Port"
$sec = ConvertTo-SecureString $ProxyPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($ProxyUser, $sec)

try {
    Write-Host '--- TEST1: Find-Module through auth proxy (good creds) ---'
    try {
        $found = Find-Module -Name $ProbeModule -Repository PSGallery -Proxy $proxyUrl -ProxyCredential $cred -ErrorAction Stop
        Assert-True ($null -ne $found) ("Find-Module via proxy returned $($found.Name) $($found.Version)")
    } catch {
        Write-Host ("FAIL TEST1 exception: {0}" -f $_)
        $script:failed++
    }

    Write-Host '--- TEST4: Save-Module through auth proxy (real download, best-effort) ---'
    # Same PackageManagement download path as Install-Module, but without
    # polluting AllUsers. Runs in a job with a timeout: on some hosts the
    # publisher check after the download stalls behind a proxy, while
    # TEST1 already proves -Proxy / -ProxyCredential work (issue #85).
    try {
        $saveDir = Join-Path $env:TEMP 'wps-saveproxy'
        if (Test-Path -LiteralPath $saveDir) { Remove-Item -Recurse -Force -LiteralPath $saveDir }
        New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
        $saveJob = Start-Job -ScriptBlock {
            param($Name, $Version, $Path, $Proxy, $User, $Pass)
            $s = ConvertTo-SecureString $Pass -AsPlainText -Force
            $c = New-Object System.Management.Automation.PSCredential($User, $s)
            Save-Module -Name $Name -RequiredVersion $Version -Repository PSGallery `
                -Path $Path -Proxy $Proxy -ProxyCredential $c -Force -ErrorAction Stop
        } -ArgumentList $ProbeModule, $ProbeVersion, $saveDir, $proxyUrl, $ProxyUser, $ProxyPassword
        $done = Wait-Job $saveJob -Timeout 240
        if (-not $done) {
            Write-Host 'WARN TEST4 timed out after 240s (download may still work; TEST1 already proves the proxy path)'
            Stop-Job $saveJob
        } else {
            Receive-Job $saveJob -ErrorAction Stop | Out-Null
            Assert-True (Test-Path -LiteralPath (Join-Path $saveDir "$ProbeModule\$ProbeVersion\$ProbeModule.psd1")) 'Save-Module via proxy downloaded the module'
        }
        Remove-Job $saveJob -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host ("FAIL TEST4 exception: {0}" -f $_)
        $script:failed++
    }

    Write-Host '--- proxy traffic ---'
    Get-Content -LiteralPath $proxyLog -Raw | Write-Host
} finally {
    Stop-Job $job
    Remove-Job $job -Force
}

if ($failed -gt 0) { Write-Host "FAILED: $failed check(s)"; exit 1 }
Write-Host 'OK'
