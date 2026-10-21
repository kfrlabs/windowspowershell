<#
.SYNOPSIS
    Parses and lints the PowerShell this module sends to nodes.

.DESCRIPTION
    Every .ps1/.psm1 under -Path is (1) parsed with the PowerShell language
    parser of the host running this script, then (2) analysed with
    PSScriptAnalyzer unless -ParseOnly is given. Exits 1 on any parse error or
    non-allow-listed finding.

    Run it under both Windows PowerShell 5.1 (the host the `powershell` Exec
    provider uses) and PowerShell 7. The inputs are produced by
    spec/unit/rendered_powershell_spec.rb (WPS_RENDER_DIR) and by files/.
    See TESTING.md.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)]
    [string[]] $Path,

    [string] $SettingsPath,

    [string] $AllowListPath,

    [switch] $ParseOnly
)

$ErrorActionPreference = 'Stop'

# Not in the param() defaults: $PSScriptRoot is empty there under
# `powershell.exe -File` (Windows PowerShell 5.1).
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $SettingsPath) { $SettingsPath = Join-Path $toolsDir 'PSScriptAnalyzerSettings.psd1' }
if (-not $AllowListPath) { $AllowListPath = Join-Path $toolsDir 'PSScriptAnalyzerAllowList.psd1' }

# Absolute paths: native tooling resolves relative ones against the process
# directory, which Set-Location does not change.
# `powershell.exe -File ... -Path a,b` delivers one "a,b" string, so split on commas.
$Path = @($Path | ForEach-Object { $_ -split ',' } | Where-Object { $_.Trim() } |
    ForEach-Object { (Resolve-Path -LiteralPath $_.Trim()).ProviderPath })

$files = foreach ($item in $Path) {
    if (Test-Path -LiteralPath $item -PathType Container) {
        Get-ChildItem -LiteralPath $item -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }
    } else {
        Get-Item -LiteralPath $item
    }
}
$files = @($files)
if ($files.Count -eq 0) {
    throw "No .ps1/.psm1 file found under: $($Path -join ', ')"
}

Write-Host ("Host: PowerShell {0} ({1}); {2} file(s)" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition, $files.Count)

$failures = 0

# 1. Parse. Read as UTF-8 explicitly: Windows PowerShell 5.1 would otherwise
#    decode a BOM-less file as ANSI when given a path.
foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref] $tokens, [ref] $parseErrors)
    foreach ($e in $parseErrors) {
        $failures++
        Write-Host ("PARSE ERROR {0}:{1}: {2}" -f $file.FullName, $e.Extent.StartLineNumber, $e.Message)
    }
}
Write-Host ("Parse: {0} error(s)" -f $failures)

# 2. PSScriptAnalyzer.
if (-not $ParseOnly) {
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        throw 'PSScriptAnalyzer is not installed (Install-Module PSScriptAnalyzer), or use -ParseOnly.'
    }
    Import-Module PSScriptAnalyzer
    Write-Host ("PSScriptAnalyzer {0}" -f (Get-Module PSScriptAnalyzer).Version)

    $allowList = @()
    if (Test-Path -LiteralPath $AllowListPath) {
        $allowList = @((Import-PowerShellDataFile -LiteralPath $AllowListPath).Allow)
    }
    $used = @{}

    $findings = foreach ($file in $files) {
        $lines = [System.IO.File]::ReadAllLines($file.FullName, [System.Text.Encoding]::UTF8)
        foreach ($r in (Invoke-ScriptAnalyzer -Path $file.FullName -Settings $SettingsPath)) {
            $sourceLine = if ($r.Line -ge 1 -and $r.Line -le $lines.Count) { $lines[$r.Line - 1] } else { '' }
            $allowed = $false
            for ($i = 0; $i -lt $allowList.Count; $i++) {
                $a = $allowList[$i]
                if ($r.RuleName -eq $a.Rule -and $file.Name -like $a.File -and $sourceLine -match $a.Line) {
                    $allowed = $true
                    $used[$i] = $true
                }
            }
            if (-not $allowed) {
                [pscustomobject]@{ File = $file.FullName; Line = $r.Line; Rule = $r.RuleName; Severity = $r.Severity; Message = $r.Message }
            }
        }
    }
    foreach ($f in $findings) {
        $failures++
        Write-Host ("{0} {1}:{2} {3}: {4}" -f $f.Severity, $f.File, $f.Line, $f.Rule, $f.Message)
    }
    # A stale allow-list entry hides nothing today but would hide a regression tomorrow.
    for ($i = 0; $i -lt $allowList.Count; $i++) {
        if (-not $used.ContainsKey($i)) {
            Write-Host ("note: allow-list entry unused: {0} / {1}" -f $allowList[$i].Rule, $allowList[$i].File)
        }
    }
    Write-Host ("PSScriptAnalyzer: {0} finding(s) after allow-list" -f @($findings).Count)
}

if ($failures -gt 0) {
    Write-Host "FAILED: $failures problem(s)"
    exit 1
}
Write-Host 'OK'
