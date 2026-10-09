# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - Unreleased

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

## [3.2.0] - 2026-08-30

### Added

- Windows Server 2025 to `operatingsystem_support` in `metadata.json`.
- `spec/classes/psget_spec.rb` covering the NuGet-provider bootstrap
  (`unless`, `timeout`, `logoutput` and proxy propagation).
- This `CHANGELOG.md` and a `LICENSE` file backing the `proprietary` license
  declared in `metadata.json` at the time.
- `.sync.yml` to document divergence from PDK defaults (currently none).

### Documentation

- `README.md` and the `ensure` param doc in `manifests/module.pp` now state
  that `ensure => present` is install-once: it installs the newest version only
  when none is present and never upgrades an already-installed one. Pin the
  version in `ensure` to move a node forward.

### Changed

- `Unblock-File` now runs at deploy time via a single refresh-only
  `Exec['windowspowershell unblock-files']` (notified by the root module and by
  every `windowspowershell::script`), instead of on every module import from
  `files/rootmodule.psm1`. Files are unblocked once per transaction when they
  change, rather than walking the whole module tree on each PowerShell session.
- `README.md`: the Description now lists both third-party module deployment
  modes in priority order (repository first, Puppet file source as the
  network-less fallback), and Limitations documents the AllUsers/64-bit
  install scope and the `powershell7` / `http_proxy` facts the module depends
  on.

## [3.1.0]

- Baseline: the version declared in `metadata.json` when this changelog was
  introduced. Prior history is available in the Git log.
