# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The generated manifest's GUID is now derived from the module name alone
  instead of name and version (issue #28). PowerShell identifies a module by
  name plus GUID and expects the GUID to stay the same from one version of a
  module to the next; with the old derivation, bumping `version` gave the new
  folder a different GUID, so two version folders of the same module declared
  two different module identities.
  - Migration: existing nodes keep the old GUID until the manifest is next
    regenerated (a script change, or a missing `.psd1`), at which point it
    changes once to the new name-derived value. Anything that pinned the old
    GUID, such as a `RequiredModules` entry with a `GUID` key, has to be
    updated.

### Fixed

- `proxy` is now typed with the new `Windowspowershell::Proxyurl` alias instead
  of `Stdlib::HTTPUrl` (issue #27). `Stdlib::HTTPUrl` accepts anything after the
  scheme, an apostrophe included, and the value is interpolated between single
  quotes in the scripts the agent runs as SYSTEM, so a crafted `proxy` could end
  the quoted string and run arbitrary PowerShell. The alias keeps the
  `http://` / `https://` requirement and refuses the apostrophe, the
  typographic single quotes PowerShell also treats as quote characters
  (U+2018 to U+201B), control characters and whitespace, at compile time.
  A URL that was valid before and contains none of those still compiles,
  including the deprecated `user:pass@host` form.

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
