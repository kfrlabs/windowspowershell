# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `proxy_credential` class parameter (issue #17): `{ username, password =>
  Sensitive }` for an authenticating proxy. The credentials are passed to
  `Install-Module` and `Install-PackageProvider` through `-ProxyCredential`,
  read from the `WPS_PROXY_USER` / `WPS_PROXY_PASSWORD` environment variables
  of the `Exec` (wrapped in `Sensitive`), so they no longer appear in the
  `command` or `unless` text, nor in Puppet reports and logs.

### Deprecated

- Credentials embedded in the `proxy` URL (`http://user:pass@host`). They are
  still accepted for now but raise a warning, because they end up in clear text
  in the `Exec` command and .NET may not honor them. Use `proxy_credential`;
  the embedded form will be removed in a future major release. Setting both
  `proxy_credential` and credentials in the URL fails the catalogue.

### Fixed

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
  - `$proxy` set → URL passed to `Install-Module`, supports authentication (e.g. `http://user:pass@proxy:port`)
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
