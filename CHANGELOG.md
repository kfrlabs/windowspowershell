# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-10-21

### Added

- Executable validation of the generated PowerShell (issue #50): a spec renders
  every Exec command, guard and profile fragment of a set of scenarios and fails
  when a template is never rendered; `tools/Test-RenderedPowerShell.ps1` parses
  them and runs PSScriptAnalyzer (one justified, narrowly matched exception for
  the proxy credential); `tools/Test-WindowsRuntime.ps1` replays them on a real
  Windows node. CI gains a `powershell` job (Linux) and a `powershell_windows`
  matrix (Windows Server 2022 and 2025, Windows PowerShell 5.1 and PowerShell 7).
  The `powershell7` fact spec now also covers a missing `%ProgramFiles%`, a
  non-Windows node and a real directory tree. The manual validation matrix is in
  `TESTING.md`.

- Co-management of the machine-wide profiles (issue #31): the README gains a
  "Co-managing the profiles" section documenting that other Puppet code can
  add its own `concat::fragment` to the profile targets
  (`$windowspowershell::profile_paths`), with the ordering convention (`00`
  header, `01`-`49` and `70`-`99` free, `50` in-house imports, `60` external
  imports) and a `profile_paths`-based example. The `manage_profiles`
  parameter documentation and the Limitations section now warn that content
  not coming from a fragment (a GPO startup script, manual edits) is removed
  on every run. No behaviour change. New specs check that extra fragments
  coexist with the header and the `Import-Module` fragments, on every managed
  profile, and that the documented pattern compiles on non-Windows nodes.

- `windowspowershell::module` now removes version folders other than `version`
  (issue #29), through a new `purge_versions` parameter (default `true`) that
  reuses the same `-Directory` filter purge as
  `windowspowershell::external_module`. Bumping `version` no longer leaves the
  old folder behind declaring a stale manifest, so the one-time manual cleanup
  step from the 1.2.0 migration note is no longer needed on nodes that run
  this version. Set `purge_versions => false` to keep old versions side by
  side. Modules created implicitly by `windowspowershell::script` also purge
  by default; declare the module explicitly with `purge_versions => false`
  first to opt out.

### Changed

- **Breaking (v2.0, issue #69):** `windowspowershell::module`'s
  `import_in_profile` now defaults to `false` instead of `true`. The module
  lives under the machine-wide module directory and exports its functions by
  name, so PowerShell auto-loads it on first use; the profile import only
  added to the startup time of every session. This is the flip the README
  announced for the next major release.
  - Migration: nodes that relied on the profile import (aliases or variables
    available at startup, functions pre-loaded) must set
    `import_in_profile => true` explicitly. `windowspowershell::external_module`
    already defaulted to `false` and is unchanged.
- **Breaking (v2.0, issue #72):** Puppet 7 is no longer supported
  (`metadata.json` now requires `puppet >= 8.0.0 < 9.0.0`). Puppet 7 is EOL,
  and keeping it forced the CI matrix onto Ruby 2.7, itself EOL. The
  `ci.yml` / `release.yml` matrices now test Puppet 8 on Ruby 3.2 only.
  - Migration: run the module with Puppet 8. No manifest change is needed.
- **Breaking (v2.0, issue #56):** `windowspowershell::script`'s `scriptname`
  is now typed `Windowspowershell::Scriptname` instead of
  `Windowspowershell::Name` with a `fail()`. A trailing `.ps1`/`.psm1` (any
  case) is still refused — the module appends `.ps1` itself — but the failure
  is now a parameter type mismatch (`parameter 'scriptname'`) instead of the
  `must not end with '.ps1' or '.psm1'` message. Dots elsewhere stay
  legitimate (`Get-Example.v2`).
- The version normalise-and-compare PowerShell helpers are now factorised
  (issue #52): `templates/_version_compare.ps1.epp` defines
  `Get-NormalizedVersion`, `Test-PinnedVersionMatch` and `Test-IsExtraVersion`
  and is rendered via `epp()` from `check_psmodule.ps1.epp`,
  `check_psmodule_versions.ps1.epp` and `purge_psmodule_versions.ps1.epp`.
  No behaviour change — verified equivalent on Windows PowerShell 5.1 across
  short, single-component, four-part and stray folder names (issue #30, #55).

### Removed

- **Breaking (v2.0, issue #57):** credentials embedded in the `proxy` URL
  (`http://user:pass@host`) are now refused at compile time by
  `Windowspowershell::Proxyurl`. They ended up in clear text in the `Exec`
  `command`/`unless` (reports) and .NET may ignore them. The deprecation
  warning from 1.2.0 (which never echoed the URL) and the `proxy_has_userinfo`
  logic are removed; a URL containing userinfo (`@` before the first `/`)
  fails with `parameter 'proxy'`.
  - Migration: move the credentials to `proxy_credential`
    (`{ username, password => Sensitive }`) with a clean `proxy` URL. Setting
    `proxy_credential` without `proxy` still fails; setting both with userinfo
    in `proxy` now fails on `parameter 'proxy'` instead of the old explicit
    `embeds credentials` message.

### Fixed

- The unreliable `OSVersion.Major -ge 10` gate of the pwsh profile was removed
  (issue #58, closes #67): `[Environment]::OSVersion` can report 6.x without an
  app-compatibility manifest, silently skipping the PSReadLine configuration.
  The gate bought nothing — PSReadLine presence and version are already guarded
  in the profile itself — so the profile now configures PSReadLine whenever the
  session is interactive. `tools/Test-OsGate.ps1`, its CI steps and its
  `TESTING.md` section are removed.

- The manifest (`.psd1`) now converges when only `author`, `companyname`,
  `version` or the GUID change (issue #45). `Exec["windowspowershell
  update-manifest ..."]` is refresh-only and the create exec is only gated on
  `creates`, so a change of those parameters touched no resource and the
  `.psd1` stayed stale indefinitely. `windowspowershell::module` now manages a
  witness file, `<version folder>\.manifest-params`, whose content is the
  SHA-256 of the manifest build command (a pure function of the parameters, so
  any future manifest flag is covered too). It notifies the manifest refresh
  and the unblock, and a missing or edited witness is rewritten the same way.
  - Migration: the witness is created on the first run after the upgrade, which
    regenerates every in-house manifest once. This is also the point where the
    name-derived GUID from issue #28 lands on nodes that had no other reason to
    regenerate. A `.psd1` that is itself corrupt or edited by hand while the
    witness is intact is still not repaired; delete the `.psd1` (or the
    witness) to force a rebuild.
  - New specs cover an `author`-only and a `companyname`-only change.

- **Breaking:** `windowspowershell::script` no longer builds the module it
  names with `ensure_resource` (issue #46). That implicit module made the
  version depend on declaration order: an explicit `windowspowershell::module`
  declared from a scope evaluated after the script's body died with Puppet's
  bare `Duplicate declaration`. The module now has to be declared explicitly
  (`windowspowershell::module { 'Acme': }` is enough for the defaults), and a
  script naming an undeclared module fails to compile with a message that
  names the module and says where to declare it. Declaring the module before
  or after the scripts in the same class stays fine, because a define body is
  evaluated after the scope that declared it.
  - Migration: add a `windowspowershell::module` for every `modulename` that
    was only ever created implicitly. Nothing changes on the node: same
    module name, same defaults, same paths.
- The generated manifest's GUID is now derived from the module name alone
  instead of name and version (issue #28). PowerShell identifies a module by
  name plus GUID and expects the GUID to stay the same from one version of a
  module to the next; with the old derivation, bumping `version` gave the new
  folder a different GUID, so two version folders of the same module declared
  two different module identities.
  - Migration: existing nodes keep the old GUID until the manifest is next
    regenerated (the first run after the issue #45 witness file lands, a script
    change, or a missing `.psd1`), at which point it changes once to the new
    name-derived value. Anything that pinned the old
    GUID, such as a `RequiredModules` entry with a `GUID` key, has to be
    updated.

- CI and release hardening (issue #32):
  - Every third-party action in `ci.yml` and `release.yml` is pinned to a full
    commit SHA, with the tag in a trailing comment, and a Dependabot
    configuration (`package-ecosystem: github-actions`) keeps them current.
  - `release.yml` now runs the same `rspec-puppet` matrix as `ci.yml` before
    publishing (Puppet 7 / Puppet 8 at the time; since reduced to Puppet 8
    only by issue #72). The tests run in separate jobs, so the `forge`
    environment and its credentials are only exposed to the final publish job.
  - `puppetlabs_spec_helper` moved from the `release_prep` to the `test` gem
    group: the `Rakefile` requires it unconditionally, so
    `BUNDLE_WITHOUT=release_prep` no longer fails with a `LoadError`.

- Profile imports no longer fail silently (issue #33). The `Import-Module`
  line that `windowspowershell::module` and
  `windowspowershell::external_module` add to the profiles used
  `-ErrorAction SilentlyContinue`, so a broken module left no trace in the
  session. It is now `-ErrorAction Stop` inside a `try`/`catch` that prints a
  `Write-Warning` naming the module and the reason, and the session still
  starts normally. Nodes see this on the next run that rewrites the profiles.

- Documentation hardening (issue #33):
  - The README and the `import_in_profile` parameter documentation of
    `windowspowershell::module` explain when the profile import is actually
    needed (aliases or variables at startup) and that otherwise module
    auto-loading already covers it, at a lower startup cost. The default
    flip itself ships in this release (issue #69).
  - New "Repository trust" section in the README, and a note on the
    `repository` parameter of `windowspowershell::external_module`: the
    repository named is trusted to execute code as `SYSTEM` because
    `Install-Module -Force` suppresses the untrusted-repository prompt, and an
    internal mirror is recommended for production.
  - Stale comments fixed: `files/rootmodule.psm1` now names the per-module
    `unblock-files` Exec, and the SysWOW64 comment moved from
    `windowspowershell::config` to `profile_paths` in `init.pp`, which it
    describes. No behaviour change.

- The `powershell7` fact documentation no longer claims to detect ZIP,
  Microsoft Store, winget and non-standard installs (issue #48). The fact has
  only ever tested `%ProgramFiles%\PowerShell\7\pwsh.exe`, which is the right
  scope: the module manages the profile at
  `C:\Program Files\PowerShell\7\profile.ps1`, and PowerShell only loads a
  machine-wide profile from its own install directory, so detecting a pwsh
  elsewhere would manage a profile it never reads. The fact comment, the
  README (Facts and Limitations), the `manage_pwsh_profile` documentation and
  the `fail()` raised when `manage_pwsh_profile => true` finds no PowerShell 7
  now all say "default location only" instead of the misleading "not detected
  (no pwsh.exe)". No behaviour change.
- `windowspowershell::external_module` with `ensure => present` (any version
  accepted) no longer treats any sub-folder of the module directory as an
  installed version (issue #55). A stray folder under `Modules\<Name>` (a
  backup, a temp folder) made the idempotency check succeed and blocked the
  install although no version was present. Only folders that parse as a
  `[version]` now count, with the same single-component normalisation
  (`2` is read as `2.0`) as the pinned checks.
- `proxy` is now typed with the new `Windowspowershell::Proxyurl` alias instead
  of `Stdlib::HTTPUrl` (issue #27). `Stdlib::HTTPUrl` accepts anything after the
  scheme, an apostrophe included, and the value is interpolated between single
  quotes in the scripts the agent runs as SYSTEM, so a crafted `proxy` could end
  the quoted string and run arbitrary PowerShell. The alias keeps the
  `http://` / `https://` requirement and refuses the apostrophe, the
  typographic single quotes PowerShell also treats as quote characters
  (U+2018 to U+201B), control characters and whitespace, at compile time.
  A URL that was valid before and contains none of those still compiles;
  the `user:pass@host` form it still accepted is removed in this release
  (issue #57).
- `Windowspowershell::Name`, `Windowspowershell::Psstring` and
  `Windowspowershell::Rootpath` now also refuse the typographic single quotes
  U+2018, U+2019, U+201A and U+201B (issue #36). PowerShell treats them as
  single-quote characters, so, like the ASCII apostrophe, they can end the
  single-quoted string a module, script or folder name, an author, a company
  name or `module_root` is interpolated into. They were rejected only for
  the proxy URL until now. A value containing one of them, which is unlikely
  but possible in a company name, now fails the catalogue at compile time.
- A pinned `windowspowershell::external_module` version with fewer segments
  than the folder PowerShellGet creates no longer reinstalls on every run
  (issue #30). The install check, the purge check and the purge itself now
  accept a folder whose name parses as `[version]` and is numerically equal
  to the pinned version with missing segments treated as zero (e.g. pin
  `2.1` matches folder `2.1.0`, pin `2` matches folder `2.0` after
  normalising the single component to two before the `[version]` cast,
  which needs major.minor), as well as the literal folder the file
  `source` backend creates. Folders that do not parse as `[version]` are
  kept, never purged, so an unexpected directory is not deleted. A
  single-component pin is also normalised for the profile
  `Import-Module -RequiredVersion` line (`2` becomes `2.0`), which is typed
  `[version]` and needs at least major.minor. If both the short and the
  normalised folder spellings end up side by side (e.g. `2.1` and `2.1.0`),
  both count as the pinned version and neither is purged: the canonical
  folder is whatever the backend creates (the normalised name for
  `repository`, the literal pin for `source`), so remove the other spelling
  once by hand. Each version component is now limited to nine digits at
  compile time, like `Windowspowershell::Moduleversion`, because
  `System.Version` parses every component as an Int32 and a tenth digit
  would overflow at Exec runtime instead; single-component pins such as `2`
  are still accepted.

- Forge tarball and fixtures locked (issues #68, #71): `.pmtignore` is now
  kept identical to `.pdkignore` (CI diffs them), `tools/check-tarball.sh`
  verifies the built tarball carries the full payload (`metadata.json`,
  `manifests/`, `files/`, `templates/`, `types/`, ...) and no dev-only
  paths (`tools/`, `TESTING.md`, `spec/fixtures`, ...), and `release.yml`
  re-verifies the artifact before `module:push`. `.fixtures.yml` pins the
  Forge fixtures inside the `metadata.json` ranges (stdlib 9.7.0,
  powershell 6.2.0, concat 9.1.0).

## [1.2.0] - 2026-10-16

### Added

- `proxy_credential` class parameter (issue #17): `{ username, password =>
  Sensitive }` for an authenticating proxy. The credentials are passed to
  `Install-Module` and `Install-PackageProvider` through `-ProxyCredential`,
  read from the `WPS_PROXY_USER` / `WPS_PROXY_PASSWORD` environment variables
  of the `Exec` (wrapped in `Sensitive`), so they no longer appear in the
  `command` or `unless` text, nor in Puppet reports and logs.

### Changed

- Clarify 1.1.0 breaking change (issue #18): 1.1.0 removed the site-provided `http_proxy` structured fact
  as a proxy source. The proxy now comes exclusively from the
  `$proxy` class parameter: `undef` (the default) goes out directly, a set
  URL is passed to `Install-Module`. A stray `http_proxy` fact on the node
  is ignored.
  - Migration: set the proxy explicitly where it was previously read from
    the fact:
    ```yaml
    windowspowershell::proxy: 'http://proxy.example.net:3128'
    ```
    In 1.0.x the module read the fact; from 1.1.0 set it explicitly
    (`undef` = direct, no proxy).
- BREAKING: `windowspowershell::module`'s `version` parameter now requires at
  least two dot-separated components, and is typed with the new
  `Windowspowershell::Moduleversion` alias instead of `Windowspowershell::Version`.
  A single number such as `version => '1'` used to compile and produce a module
  reporting `0.0.1`; now that the value reaches `-ModuleVersion`, PowerShell
  casts it to `[version]`, which requires a major and a minor component, so it
  is refused at compile time rather than failing later at Exec runtime.
  `Windowspowershell::Version` itself is unchanged and stays the (looser) type
  for `windowspowershell::external_module`; tightening it is out of scope here,
  as that would break external_module catalogues.
  - Migration for existing nodes: this does not repair modules already
    installed. One that was installed before this fix keeps its `0.0.1`
    manifest until `create-manifest` or `update-manifest` actually runs, and
    neither purges the old version folder, so remove
    `C:\Program Files\WindowsPowerShell\Modules\<Module>\<old version>\` on the
    node as the one-time step. Simply bumping `version` is not enough: it
    creates the new folder but leaves the old one behind declaring `0.0.1`, and
    `Get-Module -ListAvailable` then reports two versions of the module.

### Deprecated

- Credentials embedded in the `proxy` URL (`http://user:pass@host`). They are
  still accepted for now but raise a warning, because they end up in clear text
  in the `Exec` command and .NET may not honor them. Use `proxy_credential`;
  the embedded form will be removed in a future major release. Setting both
  `proxy_credential` and credentials in the URL fails the catalogue.

### Fixed

- `Windowspowershell::Name` now rejects Windows reserved device names
  (issue #16). `CON`, `PRN`, `AUX`, `NUL`, `COM1`-`COM9` and `LPT1`-`LPT9`
  are refused case-insensitively, with or without an extension (spaces
  between the stem and the extension do not save it, e.g. `CON .txt`),
  at compile time instead of failing at apply time. Names that merely
  start with one (`CONSOLE`, `Console-Tools`, `COM10`) still pass.
- `Get-ChildItem -Path` no longer treats `[` and `]` in a module name or in
  `module_root` as a wildcard character class (issue #15). The unblock `Exec`
  and the `Functions` scan now pass `-LiteralPath`, matching the `check_*`,
  `purge` and `uninstall` templates that already did. The scan applies its
  `.ps1` / `.psm1` extension filter in the pipeline rather than with `-Include`,
  which Windows PowerShell silently ignores when combined with `-LiteralPath`
  (it is honoured only from PowerShell Core 6.1 on). Only `.ps1` / `.psm1` files
  are kept, at any depth, and `-File` keeps directories out; the sub-folder
  layout is intentionally preserved in the manifest. A bracketed name previously
  made `update-manifest` fail to enumerate the scripts, and could silently leave
  the module tree blocked for the whole run.
- The generated PowerShell manifest now carries the configured `version`
  (issue #14). `windowspowershell::module` installed the module under a folder
  named after `version` but wrote `ModuleVersion = '0.0.1'` into the `.psd1`,
  because `New-ModuleManifest` was called without `-ModuleVersion`. A module in
  `...\Modules\Acme\1.0\` therefore reported itself as `0.0.1`, so `Get-Module
  Acme` showed the wrong version and `Import-Module Acme -RequiredVersion 1.0`
  could fail to match. `-ModuleVersion` is now passed, matching the folder the
  module is installed under. This fixes newly built manifests only: a module
  already installed on a node keeps its `0.0.1` manifest until its version
  folder is removed and rebuilt (see the migration note above).
- Profile `Import-Module` lines no longer overwrite each other when several
  modules import into the profile (issue #12). `windowspowershell::config`
  now declares each managed profile as a `concat` target with a header
  fragment, and `windowspowershell::module` / `windowspowershell::external_module`
  each contribute one `concat::fragment` per profile (orders `50` / `60`), so
  several in-house and external modules can be imported side by side.
- Regression test for issue #13: the PowerShell 7 profile keeps its PSReadLine
  header (order `00`) next to the `Import-Module` fragments (orders `50` / `60`)
  when a module imports into it. The `concat` assembly introduced for issue #12
  already fixes the behavior; no manifest change was needed.

## [1.1.0] - 2026-10-10

### Changed

- Proxy configuration now uses only the `$proxy` class parameter
  - `$proxy` `undef` → installations go out directly (no proxy)
  - `$proxy` set → URL passed to `Install-Module`, supports authentication (e.g. `http://user:pass@proxy:port`; embedded credentials deprecated in 1.2.0, see above)
  - Parameter validated at compile time via `Stdlib::HTTPUrl` type
  - Set it via Hiera or node definition
  - Removes the dependency on the external `http_proxy` fact: the module no longer reads any site-provided structured fact for proxy detection

## [1.0.0] - 2026-10-09

First public release, published independently of the internal fork this
module started from. The in-house module identity is no longer a singleton
owned by the main class: a site can now build several in-house modules side
by side, each named explicitly.

### Breaking changes

- Removed `modulename`, `version`, `companyname` and `author` from the
  `windowspowershell` class. There is no module-wide default module identity
  any more: `include windowspowershell` alone compiles and lays out nothing
  but the shared machine-wide module directory.
- Added `windowspowershell::module` (title = module name), which owns
  everything that used to be built once by `windowspowershell::install` for
  the single configured module: the module directory, the root module file,
  manifest regeneration, and file unblocking, now namespaced per module name
  so several can coexist on the same node.
- `windowspowershell::script` now requires a `modulename` parameter naming the
  `windowspowershell::module` it deploys into. A module named by a
  script that was never declared explicitly is still built automatically,
  with every default, via `ensure_resource` -- declaring
  `windowspowershell::module` by hand is only needed to override a
  default (`version`, `companyname`, `author`).
- Added `windowspowershell::external_module` for third-party modules
  (repository or file-source install, `ensure` carrying the version). The
  short `windowspowershell::module` name is reserved for in-house modules
  built from `windowspowershell::script` resources.
- Removed the bundled example scripts previously shipped under
  `files/scripts/` (Puppet agent helpers, desktop and monitoring utilities).
  They were specific to the environment this module was forked from and are
  not portable as-is; ship your own scripts via `windowspowershell::script` or
  the new `source` parameter on `windowspowershell::module` instead.
- `data/common.yaml` no longer ships a module identity. The module data layer
  now ships no override at all; every parameter already has a working,
  neutral default.
- Re-licensed from a proprietary license to Apache-2.0, and published under a
  new Forge namespace (`kfrlabs-windowspowershell`) and a new public GitHub
  repository.

### Added

- `windowspowershell::module`, a new defined type: one resource is one
  in-house module identity (see Breaking changes above).
- `source` parameter on `windowspowershell::module`: an optional
  Puppet file source that recursively, and **purgingly**, deploys a whole
  directory of scripts into `Functions` in one go -- the "dynamic" way to
  build a module, where dropping a new `.ps1` under that source is enough, no
  Puppet code change needed. Left unset (the default), `Functions` is
  populated only by individual `windowspowershell::script` resources.
- GitHub Actions CI (`ci.yml`): Puppet syntax/metadata/REFERENCE.md checks,
  `rubocop`, `puppet-lint`, and `rspec-puppet` across a Puppet 7/8 matrix on
  every push and pull request.
- GitHub Actions release workflow (`release.yml`): publishes the module to the
  Puppet Forge via `puppet-blacksmith` when a `v*.*.*` tag is pushed.
