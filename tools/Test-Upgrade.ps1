<#
.SYNOPSIS
    Validates a version upgrade of this module with a real agent.

.DESCRIPTION
    Upgrade scenario (issue #112, Gap 4): stages the previous release tag in
    place of this checkout on the modulepath, applies the previous tag's own
    spec/integration/site.pp once (exit 2, converging with the old code and
    writing the manifest witness), then swaps the current checkout back in
    and applies the current catalogue twice. The second run may change resources once (exit 2: the
    one-time manifest regeneration when the manifest command changed between
    the releases, e.g. the witness hash) or be clean already (exit 0); the
    third run must change nothing (exit 0). Functional checks then verify the
    upgraded state: the witness exists, the manifest GUID is stable across
    the upgrade (name-derived since 2.0), the manifest version and its nested
    modules, stale version folders purged, an Import-Module round-trip, and
    the profile import line.

    A stale `WpsInt\0.9` version folder is seeded before the first run so the
    upgrade also proves the purge path removes it.

    Run from Windows PowerShell 5.1 as SYSTEM (Scheduled Task): the SSH
    channel cannot host the `powershell` provider's stdin. See TESTING.md.
    On a node enrolled with a non-default environment, pass -Environment.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Site,

    [Parameter(Mandatory)]
    [string] $Modulepath,

    # Previous release tag for the upgrade span. Empty (the default) means
    # auto-derive the newest v* tag at run time, so the schedule always spans
    # the latest boundary without a hardcoded bump after each release. Pass
    # an explicit tag only to pin a boundary by hand.
    [string] $PreviousTag = '',

    [string] $ModuleRoot = 'C:\wps-int\Modules',

    [string] $Environment = ''
)

$ErrorActionPreference = 'Stop'

$Site = (Resolve-Path -LiteralPath $Site).ProviderPath
$failed = 0

function Assert-True([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $script:failed++ }
}

function Invoke-PuppetApply([string] $Label, [string] $ApplySite = $Site) {
    Write-Host "--- $Label : puppet apply $ApplySite"
    $envArgs = @()
    if ($Environment -ne '') { $envArgs = @('--environment', $Environment) }
    $output = & puppet apply --detailed-exitcodes @envArgs --modulepath $Modulepath --verbose $ApplySite 2>&1
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
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is not on PATH (needed to check out the previous tag).'
}

$RepoRoot = (git rev-parse --show-toplevel 2>&1 | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $RepoRoot)) {
    throw 'Not inside a git repository (git rev-parse --show-toplevel failed).'
}
Write-Host ("Repository root: {0}" -f $RepoRoot)
if ([string]::IsNullOrWhiteSpace($PreviousTag)) {
    # Lightweight robust fix for the hardcoded-tag drift (issue #112 review):
    # pick the newest v* tag at run time. Needs full history + tags
    # (ci.yml uses fetch-depth: 0 with fetch-tags: true; lab clones need
    # `git fetch --tags origin`).
    $tags = @(git -C $RepoRoot tag --list 'v*' --sort=-v:refname 2>&1)
    if ($LASTEXITCODE -ne 0 -or $tags.Count -eq 0 -or [string]::IsNullOrWhiteSpace($tags[0])) {
        throw "No v* tags found. Fetch tags first (git fetch --tags origin)."
    }
    $PreviousTag = $tags[0].Trim()
    Write-Host ("Auto-derived previous tag: {0}" -f $PreviousTag)
}
$tagRef = (git rev-parse --verify "refs/tags/$PreviousTag" 2>&1 | Select-Object -First 1)
if ($LASTEXITCODE -ne 0) {
    throw "Previous tag '$PreviousTag' not found. Fetch tags first (git fetch --tags origin)."
}
Write-Host ("Previous tag: {0} ({1})" -f $PreviousTag, $tagRef)

$staged = Join-Path $Modulepath 'windowspowershell'
if (-not (Test-Path -LiteralPath $staged)) {
    throw "Staged module not found at $staged (stage the checkout under its module name first, see TESTING.md)."
}

$prevWorktree = Join-Path $env:TEMP 'wps-prev-tag'
try {
    # Check out the previous tag next to this checkout, then swap the staged
    # copy: the agent under test always sees a plain modulepath entry.
    git worktree remove --force $prevWorktree 2>$null
    git -C $RepoRoot worktree add --detach $prevWorktree $PreviousTag 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "git worktree add $PreviousTag failed." }

    if (Test-Path -LiteralPath $staged) { Remove-Item -Recurse -Force -LiteralPath $staged }
    Copy-Item -Recurse -Force $prevWorktree $staged

    # Review fix (MEDIUM 1): the first (old-code) run applies the previous
    # tag's own catalogue, not the current checkout's site.pp against the old
    # module code (an old-code/new-catalog fictional combo). The current $Site
    # returns for runs 2-3 after the swap.
    $prevSite = Join-Path $prevWorktree 'spec/integration/site.pp'
    if (-not (Test-Path -LiteralPath $prevSite)) {
        throw "Previous tag catalogue not found at $prevSite."
    }
    Write-Host ("Previous tag catalogue: {0}" -f $prevSite)

    # Stale version folder: the upgrade must purge it.
    $stale = Join-Path $ModuleRoot 'WpsInt\0.9'
    New-Item -ItemType Directory -Path $stale -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $stale 'stale.txt') -Value 'stale' -Encoding UTF8

    $first = Invoke-PuppetApply "first run ($PreviousTag)" $prevSite
    Assert-True (($first -band 1) -eq 0) ("first run succeeded (exit $first)")
    Assert-True ($first -eq 2) ("first run converged with the old code (exit $first, expected 2)")

    $manifest = Join-Path $ModuleRoot 'WpsInt\1.0\WpsInt.psd1'
    $witness = Join-Path $ModuleRoot 'WpsInt\1.0\.manifest-params'
    Assert-True (Test-Path -LiteralPath $witness) 'upgrade: manifest witness written by the old code'
    $oldGuid = (Import-PowerShellDataFile -LiteralPath $manifest).GUID
    Write-Host ("manifest GUID after the old code: {0}" -f $oldGuid)

    # Swap the current checkout back in and upgrade.
    if (Test-Path -LiteralPath $staged) { Remove-Item -Recurse -Force -LiteralPath $staged }
    Copy-Item -Recurse -Force $RepoRoot $staged

    $second = Invoke-PuppetApply 'second run (upgrade to the current code)'
    Assert-True (($second -band 1) -eq 0) ("second run succeeded (exit $second)")
    # Exit 2 when the manifest command changed between the releases (the
    # witness hash follows it, so the manifest regenerates exactly once);
    # exit 0 when the upgrade changes no resource. Both converge. When the
    # run changed something, dump the manifest marker so the log shows which
    # resource moved without changing the acceptance.
    if ($second -eq 2) {
        Write-Host '--- second-run marker: manifest resource state after the upgrade'
        if (Test-Path -LiteralPath $witness) {
            Write-Host ("witness present: {0}" -f $witness)
            Get-Content -LiteralPath $witness | ForEach-Object { Write-Host ("witness: {0}" -f $_) }
        } else {
            Write-Host ("WARNING witness missing after a changed second run: {0}" -f $witness)
        }
        if (Test-Path -LiteralPath $manifest) {
            $midGuid = (Import-PowerShellDataFile -LiteralPath $manifest).GUID
            Write-Host ("manifest GUID after the second run: {0}" -f $midGuid)
        }
    }
    Assert-True (($second -eq 0) -or ($second -eq 2)) ("second run converged (exit $second, expected 0 or 2)")

    Assert-True (-not (Test-Path -LiteralPath $stale)) 'upgrade: stale version folder purged'
    Assert-True (Test-Path -LiteralPath $witness) 'upgrade: manifest witness still present'
    $newGuid = (Import-PowerShellDataFile -LiteralPath $manifest).GUID
    Assert-True ($newGuid -eq $oldGuid) 'upgrade: manifest GUID stable across the upgrade (name-derived since 2.0)'

    $third = Invoke-PuppetApply 'third run'
    Assert-True (($third -band 1) -eq 0) ("third run succeeded (exit $third)")
    Assert-True ($third -eq 0) ("third run changed nothing (exit $third, expected 0)")

    # Converged state, checked the way a user would see it.
    $data = Import-PowerShellDataFile -LiteralPath $manifest
    Assert-True ($data.ModuleVersion -eq '1.0') 'upgrade: manifest version is 1.0'
    $nested = @($data.NestedModules) -join ','
    Assert-True (($nested -match 'Get-WpsIntHello\.ps1') -and ($nested -match 'Get-WpsIntFromSource\.ps1')) 'upgrade: both scripts are nested modules'

    $env:PSModulePath = "$ModuleRoot;$env:PSModulePath"
    Import-Module WpsInt -Force
    Assert-True ((Get-WpsIntHello) -eq 'hello') 'upgrade: content-deployed script runs'
    Assert-True ((Get-WpsIntFromSource) -eq 'from-source') 'upgrade: source-deployed script runs'
    Remove-Module WpsInt -Force -ErrorAction SilentlyContinue

    $profilePath = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
    Assert-True (Test-Path -LiteralPath $profilePath) 'upgrade: machine-wide profile written'
    $profileText = [System.IO.File]::ReadAllText($profilePath)
    Assert-True ($profileText -match 'WpsInt\.psd1') 'upgrade: WpsInt import line present'
}
finally {
    # The worktree metadata lives in this checkout: always remove it. The
    # staged copy keeps whichever tree the last completed step put there.
    git -C $RepoRoot worktree remove --force $prevWorktree 2>$null
}

if ($failed -gt 0) { Write-Host "FAILED: $failed check(s)"; exit 1 }
Write-Host 'OK'
