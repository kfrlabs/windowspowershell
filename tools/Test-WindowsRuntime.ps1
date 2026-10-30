<#
.SYNOPSIS
    Runs the rendered "runtime" scenario scripts on a real Windows node.

.DESCRIPTION
    Builds a throw-away module tree under C:\wps-ci\Modules (the module_root of
    the `runtime` scenario in spec/unit/rendered_powershell_spec.rb), then
    replays the rendered Exec commands and their unless/onlyif guards the way
    the `powershell` provider does: script text on stdin of Windows PowerShell
    (or of PowerShell 7 with `-Shell pwsh`, issue #112). Everything is
    offline: no gallery access is needed.

    It also replays the repository install checks of the
    `external_from_repository` scenario (sibling folder from the same render
    run, see -RepositoryRenderedPath) against fixture trees, with only their
    $moduleDir assignment repointed so the real AllUsers directory is never
    touched: empty, partial and corrupt version folders must reinstall
    (exit 1), while a healthy manifest satisfies the check (exit 0).

    Run it from Windows PowerShell 5.1 on every supported Windows Server
    release. -RenderedPath points at the `runtime` folder produced with
    WPS_RENDER_DIR. -Shell replays the shared subset (purge, manifest,
    unblock, absent, repository checks) through PowerShell 7 instead: the
    provider itself only ever runs under 5.1, so 5.1 stays the primary leg.
    See TESTING.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RenderedPath,

    [string] $Root = 'C:\wps-ci\Modules',

    [string] $RootModule,

    # Sibling of the runtime folder, written by the same
    # spec/unit/rendered_powershell_spec.rb run (WPS_RENDER_DIR).
    [string] $RepositoryRenderedPath,

    # Sibling of the runtime folder, written by the same
    # spec/unit/rendered_powershell_spec.rb run (WPS_RENDER_DIR).
    [string] $AclRenderedPath,

    # Issue #112, Gap 3: engine replaying the rendered scripts. The
    # `powershell` provider only ever runs under Windows PowerShell 5.1, so
    # 'powershell' stays the primary leg; 'pwsh' replays the shared subset
    # (purge, manifest, unblock, absent, repository checks) through
    # PowerShell 7 to prove the rendered scripts are cross-edition clean.
    [ValidateSet('powershell', 'pwsh')]
    [string] $Shell = 'powershell'
)

$ErrorActionPreference = 'Stop'

# Not in the param() defaults: $PSScriptRoot is empty there under
# `powershell.exe -File` (Windows PowerShell 5.1).
if (-not $RootModule) {
    $RootModule = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\files\rootmodule.psm1'
}
$RenderedPath = (Resolve-Path -LiteralPath $RenderedPath).ProviderPath
if (-not $RepositoryRenderedPath) {
    $RepositoryRenderedPath = Join-Path (Split-Path -Parent $RenderedPath) 'external_from_repository'
}
$RepositoryRenderedPath = (Resolve-Path -LiteralPath $RepositoryRenderedPath).ProviderPath
if (-not $AclRenderedPath) {
    $AclRenderedPath = Join-Path (Split-Path -Parent $RenderedPath) 'module_root_acl'
}
$AclRenderedPath = (Resolve-Path -LiteralPath $AclRenderedPath).ProviderPath
$shellExe = if ($Shell -eq 'pwsh') { 'pwsh.exe' } else { 'powershell.exe' }
$failed = 0

function Get-RenderedScriptPath([string] $Pattern) {
    $hits = @(Get-ChildItem -LiteralPath $RenderedPath -Filter $Pattern)
    if ($hits.Count -ne 1) { throw "Expected exactly one rendered script for '$Pattern', found $($hits.Count)" }
    $hits[0].FullName
}

# Same contract as the provider: the script is fed to the engine on stdin.
# Under -Shell powershell that engine is exactly the provider's host.
function Invoke-Rendered([string] $Pattern) {
    $path = Get-RenderedScriptPath $Pattern
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 |
        & $shellExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command - | Out-Null
    $LASTEXITCODE
}

function Assert-True([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $script:failed++ }
}

function Assert-Exit([string] $Pattern, [int] $Expected, [string] $Message) {
    $actual = Invoke-Rendered $Pattern
    Assert-True ($actual -eq $Expected) "$Message (exit $actual, expected $Expected)"
}

# Issue #107: replays the manifest build and returns its merged output, so a
# failed build can assert on the file-and-line message. $ErrorActionPreference
# is 'Stop' in this script, which would turn the merged stderr records into a
# terminating error here, so the preference is relaxed in this scope only.
function Invoke-RenderedWithOutput([string] $Pattern) {
    $ErrorActionPreference = 'Continue'
    $path = Get-RenderedScriptPath $Pattern
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 |
        & $shellExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command - 2>&1
}

# Issue #106: the repository install check (external_from_repository scenario)
# hardcodes the AllUsers module directory, which a throw-away tree must not
# pollute, so the check runs with only its `$moduleDir = '...'` assignment
# repointed at the fixture tree. Every other line runs exactly as rendered,
# on stdin like the provider does.
function Get-RepositoryScriptPath([string] $Pattern) {
    $hits = @(Get-ChildItem -LiteralPath $RepositoryRenderedPath -Filter $Pattern)
    if ($hits.Count -ne 1) { throw "Expected exactly one rendered repository script for '$Pattern', found $($hits.Count)" }
    $hits[0].FullName
}

function Invoke-RepositoryCheck([string] $Pattern, [string] $ModuleDir) {
    $path = Get-RepositoryScriptPath $Pattern
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $pattern = '(?m)^' + [regex]::Escape('$moduleDir = ') + "'.*'\r?$"
    # Escape $ as $$ so a $ in the directory (legal in Windows paths,
    # e.g. C:\wps$ci) survives the -replace replacement as a literal.
    $replacement = '$$moduleDir = ''{0}''' -f ($ModuleDir.Replace("'", "''") -replace '\$', '$$$$')
    $repointed = $text -replace $pattern, $replacement
    $repointed | & $shellExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command - | Out-Null
    $LASTEXITCODE
}

function Assert-RepositoryExit([string] $Pattern, [string] $ModuleDir, [int] $Expected, [string] $Message) {
    $actual = Invoke-RepositoryCheck $Pattern $ModuleDir
    Assert-True ($actual -eq $Expected) "$Message (exit $actual, expected $Expected)"
}

# Issue #133: the rendered ACL scripts hardcode C:\wps-acl\Modules, which a
# throw-away replay must not touch, so they run with only their
# `$aclRoot = '...'` assignment repointed (same technique as
# Invoke-RepositoryCheck). Every other line runs exactly as rendered.
function Get-AclScriptPath([string] $Pattern) {
    $hits = @(Get-ChildItem -LiteralPath $AclRenderedPath -Filter $Pattern)
    if ($hits.Count -ne 1) { throw "Expected exactly one rendered ACL script for '$Pattern', found $($hits.Count)" }
    $hits[0].FullName
}

function Invoke-AclScript([string] $Pattern, [string] $AclRoot) {
    $path = Get-AclScriptPath $Pattern
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $pattern = '(?m)^' + [regex]::Escape('$aclRoot = ') + "'.*'\r?$"
    $replacement = '$$aclRoot = ''{0}''' -f ($AclRoot.Replace("'", "''") -replace '\$', '$$$$')
    $repointed = $text -replace $pattern, $replacement
    $repointed | & $shellExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command - | Out-Null
    $LASTEXITCODE
}

function Assert-AclExit([string] $Pattern, [string] $AclRoot, [int] $Expected, [string] $Message) {
    $actual = Invoke-AclScript $Pattern $AclRoot
    Assert-True ($actual -eq $Expected) "$Message (exit $actual, expected $Expected)"
}

function New-Dir([string] $Path) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }

Write-Host ("Host: PowerShell {0} ({1}); replay engine: {2} on {3}" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition, $shellExe, (Get-CimInstance Win32_OperatingSystem).Caption)

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
    # Issue #107: a syntactically broken script fails the manifest build
    # without touching the existing .psd1 (fail closed).
    Set-Content -LiteralPath (Join-Path $smoke '1.4\Functions\Get-WpsBroken.ps1') -Value 'function Get-WpsBroken {'
    $psd1Hash = (Get-FileHash -LiteralPath $psd1 -Algorithm SHA256).Hash
    $brokenOutput = @(Invoke-RenderedWithOutput '*update-manifest_WpsSmoke_command*')
    $brokenExit = $LASTEXITCODE
    $brokenText = ($brokenOutput | ForEach-Object { "$_" }) -join "`n"
    Assert-True ($brokenExit -ne 0) ("manifest: broken script fails the build (exit {0}, expected non-zero)" -f $brokenExit)
    Assert-True ($brokenText -match 'PARSE ERROR' -and $brokenText -match 'Get-WpsBroken[^:\r\n]*:\d+') 'manifest: failure names the broken file and line'
    Assert-True ((Get-FileHash -LiteralPath $psd1 -Algorithm SHA256).Hash -eq $psd1Hash) 'manifest: .psd1 byte-identical after the failed build'
    Remove-Item -LiteralPath (Join-Path $smoke '1.4\Functions\Get-WpsBroken.ps1') -Force
    Assert-Exit '*update-manifest_WpsSmoke_command*' 0 'manifest: build is green again once the broken script is gone'
    # Issue #135, step 1: a script that defines no function of its own name
    # fails the manifest build without touching the existing .psd1.
    Set-Content -LiteralPath (Join-Path $smoke '1.4\Functions\Get-WpsMismatch.ps1') -Value 'function Get-SomethingElse { "x" }'
    $mismatchHash = (Get-FileHash -LiteralPath $psd1 -Algorithm SHA256).Hash
    $mismatchOutput = @(Invoke-RenderedWithOutput '*update-manifest_WpsSmoke_command*')
    $mismatchExit = $LASTEXITCODE
    $mismatchText = ($mismatchOutput | ForEach-Object { "$_" }) -join "`n"
    Assert-True ($mismatchExit -ne 0) ("manifest: mismatched name fails the build (exit {0}, expected non-zero)" -f $mismatchExit)
    Assert-True ($mismatchText -match 'CONTRACT ERROR' -and $mismatchText -match 'Get-WpsMismatch') 'manifest: failure names the mismatched file'
    Assert-True ((Get-FileHash -LiteralPath $psd1 -Algorithm SHA256).Hash -eq $mismatchHash) 'manifest: .psd1 byte-identical after the mismatched build'
    Remove-Item -LiteralPath (Join-Path $smoke '1.4\Functions\Get-WpsMismatch.ps1') -Force
    # Issue #135, step 1: a duplicated base name fails the manifest build
    # without touching the existing .psd1.
    Set-Content -LiteralPath (Join-Path $smoke '1.4\Functions\Sub\Get-WpsA.ps1') -Value 'function Get-WpsA { "dup" }'
    $duplicateHash = (Get-FileHash -LiteralPath $psd1 -Algorithm SHA256).Hash
    $duplicateOutput = @(Invoke-RenderedWithOutput '*update-manifest_WpsSmoke_command*')
    $duplicateExit = $LASTEXITCODE
    $duplicateText = ($duplicateOutput | ForEach-Object { "$_" }) -join "`n"
    Assert-True ($duplicateExit -ne 0) ("manifest: duplicate name fails the build (exit {0}, expected non-zero)" -f $duplicateExit)
    Assert-True ($duplicateText -match 'Duplicate function names' -and $duplicateText -match 'Get-WpsA') 'manifest: failure names the duplicated function'
    Assert-True ((Get-FileHash -LiteralPath $psd1 -Algorithm SHA256).Hash -eq $duplicateHash) 'manifest: .psd1 byte-identical after the duplicated build'
    Remove-Item -LiteralPath (Join-Path $smoke '1.4\Functions\Sub\Get-WpsA.ps1') -Force
    # Issue #135, step 1: the duplicate check is case-insensitive, matching
    # PowerShell function resolution.
    Set-Content -LiteralPath (Join-Path $smoke '1.4\Functions\Sub\get-wpsa.ps1') -Value 'function Get-WpsA { "dup-lower" }'
    $caseInsensitiveHash = (Get-FileHash -LiteralPath $psd1 -Algorithm SHA256).Hash
    $caseInsensitiveOutput = @(Invoke-RenderedWithOutput '*update-manifest_WpsSmoke_command*')
    $caseInsensitiveExit = $LASTEXITCODE
    $caseInsensitiveText = ($caseInsensitiveOutput | ForEach-Object { "$_" }) -join "`n"
    Assert-True ($caseInsensitiveExit -ne 0) ("manifest: case-insensitive duplicate fails the build (exit {0}, expected non-zero)" -f $caseInsensitiveExit)
    Assert-True ($caseInsensitiveText -match 'Duplicate function names' -and $caseInsensitiveText -match 'Get-WpsA') 'manifest: failure names the case-insensitive duplicate'
    Assert-True ((Get-FileHash -LiteralPath $psd1 -Algorithm SHA256).Hash -eq $caseInsensitiveHash) 'manifest: .psd1 byte-identical after the case-insensitive duplicate'
    Remove-Item -LiteralPath (Join-Path $smoke '1.4\Functions\Sub\get-wpsa.ps1') -Force
    # Issue #135, step 1: the duplicate check spans extensions, so Foo.ps1
    # and Foo.psm1 collide.
    Set-Content -LiteralPath (Join-Path $smoke '1.4\Functions\Sub\Get-WpsB.psm1') -Value 'function Get-WpsB { "dup-psm1" }'
    $crossExtensionHash = (Get-FileHash -LiteralPath $psd1 -Algorithm SHA256).Hash
    $crossExtensionOutput = @(Invoke-RenderedWithOutput '*update-manifest_WpsSmoke_command*')
    $crossExtensionExit = $LASTEXITCODE
    $crossExtensionText = ($crossExtensionOutput | ForEach-Object { "$_" }) -join "`n"
    Assert-True ($crossExtensionExit -ne 0) ("manifest: cross-extension duplicate fails the build (exit {0}, expected non-zero)" -f $crossExtensionExit)
    Assert-True ($crossExtensionText -match 'Duplicate function names' -and $crossExtensionText -match 'Get-WpsB') 'manifest: failure names the cross-extension duplicate'
    Assert-True ((Get-FileHash -LiteralPath $psd1 -Algorithm SHA256).Hash -eq $crossExtensionHash) 'manifest: .psd1 byte-identical after the cross-extension duplicate'
    Remove-Item -LiteralPath (Join-Path $smoke '1.4\Functions\Sub\Get-WpsB.psm1') -Force
    # Issue #135, step 1: an extra helper function next to the contracted one
    # stays allowed.
    Set-Content -LiteralPath (Join-Path $smoke '1.4\Functions\Get-WpsHelper.ps1') -Value "function Get-WpsHelper { 'ok' }`nfunction Get-WpsHelperInternal { 'internal' }`n"
    Assert-Exit '*update-manifest_WpsSmoke_command*' 0 'manifest: extra helper function is allowed'
    Remove-Item -LiteralPath (Join-Path $smoke '1.4\Functions\Get-WpsHelper.ps1') -Force
    Assert-Exit '*update-manifest_WpsSmoke_command*' 0 'manifest: build is green again once the helper script is gone'
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

    # Issue #106: an empty or partial version folder must not satisfy the
    # repository install check. The fixtures replay the rendered Pinned
    # (2.1.0) and Latest (ensure => present) checks with only $moduleDir
    # repointed (see Invoke-RepositoryCheck). Offline: Test-Path plus
    # Test-ModuleManifest, no gallery access.
    $checkRoot = Join-Path $Root 'WpsCheck'
    if (Test-Path -LiteralPath $checkRoot) { Remove-Item -LiteralPath $checkRoot -Recurse -Force }

    $pinnedDir = Join-Path $checkRoot 'Pinned'
    $pinnedVersion = Join-Path $pinnedDir '2.1.0'
    New-Dir $pinnedVersion
    Assert-RepositoryExit '*install_Pinned_unless*' $pinnedDir 1 'check: empty version folder reinstalls'
    Set-Content -LiteralPath (Join-Path $pinnedVersion 'Pinned.psm1') -Value "function Get-Pinned { 'pinned' }`n"
    Assert-RepositoryExit '*install_Pinned_unless*' $pinnedDir 1 'check: partial folder without a manifest reinstalls'
    Set-Content -LiteralPath (Join-Path $pinnedVersion 'Pinned.psd1') -Value 'this is not a manifest'
    Assert-RepositoryExit '*install_Pinned_unless*' $pinnedDir 1 'check: corrupt manifest reinstalls'
    Remove-Item -LiteralPath (Join-Path $pinnedVersion 'Pinned.psd1') -Force
    New-ModuleManifest -Path (Join-Path $pinnedVersion 'Pinned.psd1') `
        -ModuleVersion '2.1.0' -GUID '22222222-3333-4444-5555-666666666666' `
        -Author 'CI' -CompanyName 'CI' -Description 'Issue106 runtime fixture.' `
        -RootModule 'Pinned.psm1' -FunctionsToExport @('Get-Pinned')
    Assert-RepositoryExit '*install_Pinned_unless*' $pinnedDir 0 'check: healthy manifest satisfies the pin'

    $latestDir = Join-Path $checkRoot 'Latest'
    $latestVersion = Join-Path $latestDir '1.0'
    New-Dir $latestVersion
    Assert-RepositoryExit '*install_Latest_unless*' $latestDir 1 'check: empty folder does not satisfy present'
    Set-Content -LiteralPath (Join-Path $latestVersion 'Latest.psm1') -Value "function Get-Latest { 'latest' }`n"
    New-ModuleManifest -Path (Join-Path $latestVersion 'Latest.psd1') `
        -ModuleVersion '1.0' -GUID '33333333-4444-5555-6666-777777777777' `
        -Author 'CI' -CompanyName 'CI' -Description 'Issue106 runtime fixture.' `
        -RootModule 'Latest.psm1' -FunctionsToExport @('Get-Latest')
    Assert-RepositoryExit '*install_Latest_unless*' $latestDir 0 'check: healthy manifest satisfies present'

    # Bracketed name: wildcard names are excluded from the Test-ModuleManifest
    # parse (it rejects wildcards in RootModule, which would reinstall a
    # healthy wildcard module on every run), so for those names the .psd1
    # only has to exist. Uses the .NET API because New-Item has no
    # -LiteralPath on 5.1 and New-ModuleManifest -Path rejects brackets.
    $bracketDir = Join-Path $checkRoot 'Bracket[Beta]'
    $bracketVersion = Join-Path $bracketDir '1.0.0'
    [void][System.IO.Directory]::CreateDirectory($bracketVersion)
    Assert-RepositoryExit '*install_Bracket*_unless*' $bracketDir 1 'check: empty bracketed version folder reinstalls'
    Set-Content -LiteralPath (Join-Path $bracketVersion 'Bracket[Beta].psm1') -Value "function Get-BracketBeta { 'bracket' }`n"
    Assert-RepositoryExit '*install_Bracket*_unless*' $bracketDir 1 'check: partial bracketed folder without a manifest reinstalls'
    Set-Content -LiteralPath (Join-Path $bracketVersion 'Bracket[Beta].psd1') -Value "@{ ModuleVersion = '1.0.0' }`n"
    Assert-RepositoryExit '*install_Bracket*_unless*' $bracketDir 0 'check: bracketed folder with a psd1 satisfies the pin (manifest parse excluded)'

    # Issue #133: opt-in ACL hardening replay on a throw-away directory.
    # Needs an elevated host: Set-Acl requires a privilege the suite
    # already assumes everywhere else.
    $aclRoot = Join-Path $Root 'AclRoot'
    if (Test-Path -LiteralPath $aclRoot) { Remove-Item -LiteralPath $aclRoot -Recurse -Force }
    New-Dir $aclRoot
    Assert-AclExit '*manage_module_root_acl_unless*' $aclRoot 1 'acl: loose inherited ACL is drift'
    Assert-AclExit '*manage_module_root_acl_command*' $aclRoot 0 'acl: apply runs'
    Assert-AclExit '*manage_module_root_acl_unless*' $aclRoot 0 'acl: apply is idempotent'
    $acl = Get-Acl -LiteralPath $aclRoot
    Assert-True ($acl.AreAccessRulesProtected) 'acl: inheritance is disabled'
    Assert-True ($acl.Access.Count -eq 2) 'acl: no entry besides the two enforced ones'
    $aclSids = @($acl.Access | ForEach-Object {
        $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } | Sort-Object)
    Assert-True (($aclSids -join ',') -eq 'S-1-5-18,S-1-5-32-544') 'acl: exactly SYSTEM and Administrators FullControl'
    $allowFull = @($acl.Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and $_.FileSystemRights -eq 'FullControl'
    })
    Assert-True ($allowFull.Count -eq 2) 'acl: both entries are Allow FullControl'

    # Content deployed after the hardened run inherits the two entries.
    $aclChild = Join-Path $aclRoot 'probe.txt'
    Set-Content -LiteralPath $aclChild -Value 'probe'
    $childSids = @((Get-Acl -LiteralPath $aclChild).Access | ForEach-Object {
        $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } | Sort-Object)
    Assert-True (($childSids -join ',') -eq 'S-1-5-18,S-1-5-32-544') 'acl: later content inherits the two entries'

    # Drift (an extra explicit entry) is detected and restored.
    $drift = Get-Acl -LiteralPath $aclRoot
    $users = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
    $driftRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $users, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $drift.AddAccessRule($driftRule)
    Set-Acl -LiteralPath $aclRoot -AclObject $drift
    Assert-AclExit '*manage_module_root_acl_unless*' $aclRoot 1 'acl: extra entry is drift'
    Assert-AclExit '*manage_module_root_acl_command*' $aclRoot 0 'acl: apply restores the two entries'
    Assert-AclExit '*manage_module_root_acl_unless*' $aclRoot 0 'acl: restored state is idempotent'
}
finally {
    if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
}

if ($failed -gt 0) { Write-Host "FAILED: $failed check(s)"; exit 1 }
Write-Host 'OK'
