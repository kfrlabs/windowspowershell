<#
.SYNOPSIS
    Unit tests for the shared version normalise-and-compare helpers.

.DESCRIPTION
    Dot-sources the per-pin renderings of
    templates/_version_compare.ps1.epp and checks
    Test-PinnedVersionMatch / Test-IsExtraVersion against a behaviour table
    (issue #139). The renderings are produced by the CI `powershell` job
    (Linux, `puppet epp render` per pin) into .rendered-powershell/
    version-compare/ and travel to the Windows legs inside the existing
    `rendered-powershell` artifact, so no Ruby/Puppet is needed on the
    replay host. For a local run, render them first, e.g.:
    foreach ($pin in '2.1','2.3','2','1.999999999') {
        bundle exec puppet epp render --values "{ version => '$pin' }" templates/_version_compare.ps1.epp |
            Set-Content -Path ".rendered-powershell/version-compare/VersionCompare.$pin.ps1" -Encoding utf8
    }
    then run this file with -RenderedDir pointing there.

    Pure functions, milliseconds per row. Runs under Windows PowerShell 5.1
    (the host the `powershell` provider uses) and PowerShell 7.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RenderedDir
)

# Pester 5 syntax (Should -Be operator form) throughout: the 5.1 inbox
# module on some hosts is older, so fail early with a clear message.
$minimumPester = [version]'5.0'
$availablePester = Get-Module -ListAvailable -Name Pester |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($null -eq $availablePester -or $availablePester.Version -lt $minimumPester) {
    $found = if ($availablePester) { $availablePester.Version } else { 'none' }
    throw ("VersionCompare.Tests needs Pester >= {0} (found: {1}). Bootstrap it first, e.g. ./tools/Install-PSScriptAnalyzer.ps1 -Name Pester." -f
        $minimumPester, $found)
}
Import-Module Pester -MinimumVersion $minimumPester -ErrorAction Stop

Describe 'Version normalise-and-compare helpers (issue #139)' {
    BeforeAll {
        # One rendering per pin (see .SYNOPSIS): file names carry the pin
        # because Test-PinnedVersionMatch reads it from script scope.
        $script:helperFile = @{}
        foreach ($pin in @('2.1', '2.3', '2', '1.999999999')) {
            $path = Join-Path $RenderedDir ("VersionCompare.{0}.ps1" -f $pin)
            if (-not (Test-Path -LiteralPath $path)) {
                throw ("Rendered helper not found: {0} (render it first, see the .SYNOPSIS)." -f $path)
            }
            $script:helperFile[$pin] = $path
        }
    }

    It '<Pin> vs <Folder> -> match=<ExpectedMatch> extra=<ExpectedExtra>' -TestCases @(
        # Pin 2.1: exact, normalised and neighbouring folders.
        @{ Pin = '2.1'; Folder = '2.1.0'; ExpectedMatch = $true; ExpectedExtra = $false }
        @{ Pin = '2.1'; Folder = '2.1'; ExpectedMatch = $true; ExpectedExtra = $false }
        @{ Pin = '2.1'; Folder = '2.10.0'; ExpectedMatch = $false; ExpectedExtra = $true }
        # Pin 2.3 keeps the normalised 2.3.0 folder.
        @{ Pin = '2.3'; Folder = '2.3.0'; ExpectedMatch = $true; ExpectedExtra = $false }
        # A single-component pin normalises to 2.0 before casting.
        @{ Pin = '2.1'; Folder = '2.1.0.1'; ExpectedMatch = $false; ExpectedExtra = $true }
        @{ Pin = '2.1'; Folder = '2.1.0.0'; ExpectedMatch = $true; ExpectedExtra = $false }
        @{ Pin = '2'; Folder = '2.0'; ExpectedMatch = $true; ExpectedExtra = $false }
        # Unparseable folders never match and are never purged.
        @{ Pin = '2.1'; Folder = 'not-a-version'; ExpectedMatch = $false; ExpectedExtra = $false }
        # Nine-digit components still fit Int32, so they compare numerically.
        @{ Pin = '1.999999999'; Folder = '1.999999999.0'; ExpectedMatch = $true; ExpectedExtra = $false }
        @{ Pin = '2.1'; Folder = '2.1.999999999'; ExpectedMatch = $false; ExpectedExtra = $true }
    ) {
        param($Pin, $Folder, $ExpectedMatch, $ExpectedExtra)

        . $script:helperFile[$Pin]

        (Test-PinnedVersionMatch $Folder) | Should -Be $ExpectedMatch
        # Extra is the negation of match, except unparseable folders, which
        # are kept (never purged).
        (Test-IsExtraVersion $Folder) | Should -Be $ExpectedExtra
    }
}
