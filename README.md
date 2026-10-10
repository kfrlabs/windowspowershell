# windowspowershell

[![CI](https://github.com/kfrlabs/windowspowershell/actions/workflows/ci.yml/badge.svg)](https://github.com/kfrlabs/windowspowershell/actions/workflows/ci.yml)
[![Release to the Puppet Forge](https://github.com/kfrlabs/windowspowershell/actions/workflows/release.yml/badge.svg)](https://github.com/kfrlabs/windowspowershell/actions/workflows/release.yml)
[![Puppet Forge version](https://img.shields.io/puppetforge/v/kfrlabs/windowspowershell.svg)](https://forge.puppet.com/modules/kfrlabs/windowspowershell)
[![Puppet Forge downloads](https://img.shields.io/puppetforge/dt/kfrlabs/windowspowershell.svg)](https://forge.puppet.com/modules/kfrlabs/windowspowershell)
[![License: Apache-2.0](https://img.shields.io/github/license/kfrlabs/windowspowershell.svg)](LICENSE)
[![Puppet >= 7.0, < 9.0](https://img.shields.io/badge/puppet-%3E%3D7.0_%3C9.0-blue.svg)](metadata.json)
[![PDK 3.4.0](https://img.shields.io/badge/PDK-3.4.0-orange.svg)](https://puppet.com/docs/pdk/latest/pdk.html)
[![Windows 2016–2025, 10/11](https://img.shields.io/badge/windows-2016--2025_%7C_10%2F11-0078D6.svg?logo=windows)](metadata.json)

## Table of Contents

1. [Description](#description)
2. [Usage](#usage)
3. [Reference](#reference)
4. [Limitations](#limitations)

## Description

Manages the Windows PowerShell environment on Windows nodes:

- the machine-wide profiles (Windows PowerShell 5.1 and PowerShell 7);
- one or more **in-house PowerShell modules**, each built from `.ps1` scripts
  deployed by Puppet, with its manifest (`.psd1`) regenerated automatically;
- **third-party PowerShell modules**, installed from a PowerShell repository
  (the PowerShell Gallery by default) or, for nodes without network access,
  deployed from a Puppet file source.

There is no module-wide default identity and no mandatory parameter anywhere:
`include windowspowershell` alone compiles and lays out nothing but the shared
machine-wide module directory. Every in-house module is its own resource
(`windowspowershell::module`), named by its own title, and every script
says explicitly which in-house module it belongs to.

## Usage

The module exposes one class and three defined types. The defined types that
manage something concrete (`windowspowershell::script`,
`windowspowershell::external_module`) are ensurable, so adding and retiring something is
the same resource with a different `ensure`.

```puppet
include windowspowershell
```

### In-house modules: `windowspowershell::module`

One resource is one module identity. Declaring it explicitly is only needed to
override a default (`version`, `companyname`, `author`); otherwise, naming the
module from a `windowspowershell::script` is enough and it is built with every
default.

```puppet
windowspowershell::module { 'Acme':
  version     => '1.2',
  companyname => 'Acme Corp',
  author      => 'Platform Team',
}
```

### Scripts: `windowspowershell::script`

A script becomes a function of the in-house module named in `modulename`,
which is mandatory: there is no default module to fall back to. The resource
title is the function name.

```puppet
windowspowershell::script { 'Get-DiskUsage':
  modulename => 'Acme',
  content    => file('profile/powershell/Get-DiskUsage.ps1'),
}

# Grouped in a sub-folder, sourced from a Puppet file server
windowspowershell::script { 'Get-WUParams':
  modulename => 'Acme',
  folder     => 'Windowsupdate',
  source     => 'puppet:///modules/windowsupdate/scripts/Get-WUParams.ps1',
}

# Retire a script that is no longer shipped
windowspowershell::script { 'Get-OldThing':
  modulename => 'Acme',
  ensure     => absent,
}
```

Exactly one of `content` or `source` is required when `ensure => present`.

A module named by a script that was never declared explicitly is built with
every default -- the same `ensure_resource` pattern `windowspowershell::external_module`
uses for the shared machine-wide module directory.

### Building a module dynamically from a whole directory

For a whole tree of scripts instead of one resource per script, pass a Puppet
file `source` straight to `windowspowershell::module`: it recurses and
**purges** `Functions` from that source, preserving the source's own
sub-folder layout. Drop a new `.ps1` under that directory and it ships on the
next Puppet run, with no Puppet code change.

```puppet
windowspowershell::module { 'Acme':
  source => 'puppet:///modules/profile/acme-scripts',
}
```

Because this copy purges the whole `Functions` directory, do not mix it with
`windowspowershell::script` resources naming the same module: each would strip
what the other deployed on the next run. Pick one mechanism per module.

### External modules: `windowspowershell::external_module`

One resource manages one **module**, not one version. `ensure` carries the
version the way it does on the `package` type, and by default every other
version found side by side is removed.

```puppet
# From the PowerShell Gallery
windowspowershell::external_module { 'PSWindowsUpdate':
  ensure     => '2.2.1.5',
  repository => 'PSGallery',
}

# By copying files, for nodes that cannot reach a repository
windowspowershell::external_module { 'PSWindowsUpdate':
  ensure => '2.2.1.5',
  source => 'puppet:///modules/windowsupdate/PSWindowsUpdate/2.2.1.5/',
}

# Remove every version
windowspowershell::external_module { 'PSWindowsUpdate':
  ensure => absent,
}
```

`ensure => absent` unregisters the module from PowerShellGet
(`Uninstall-Module`) so `Get-InstalledModule` stops listing it, then removes the
whole tree under the machine-wide module directory -- which also clears versions
deployed by file copy that PowerShellGet never recorded.

`repository` and `source` are mutually exclusive. `ensure => present` means
"any version" and needs a `repository`; the file backend always needs an
explicit version, since it has to know which directory to populate.

`ensure => present` is install-once: it installs the newest version only when
none is present and never upgrades an already-installed one on later runs. To
move a node to a newer version, pin that version in `ensure`.

There is no `latest`. Resolving it means a `Find-Module` call on every Puppet
run, and it lets two nodes drift onto different versions depending on the day
they last ran. Pin the version and bump it in the manifest.

Set `purge_versions => false` for the modules that genuinely need several
versions installed at once.

The module only manages the **AllUsers** scope
(`C:\Program Files\WindowsPowerShell\Modules`): install, idempotency check and
purge all act on that directory alone. It has no opinion on copies of the same
module found elsewhere in `PSModulePath` (a user profile's
`Documents\WindowsPowerShell\Modules`, `System32`, or paths added by third-party
applications). Such a copy neither satisfies the check nor gets purged.

#### Proxy

`Install-Module` runs on .NET, whose default proxy is the **WinINET** setting
of the account running the agent. The agent runs as LocalSystem, which never
sees an interactive user's Internet Options, and it ignores the machine-wide
**WinHTTP** proxy (`netsh winhttp set proxy`) entirely. The proxy therefore has
to be passed to `Install-Module` explicitly.

The class does that from the `$proxy` parameter. Nodes without that parameter go out directly. The `$proxy` parameter overrides any autodetection.

#### Bootstrap

Installing from a repository pulls in `windowspowershell::psget`, which
installs the NuGet package provider that Windows Server 2016 lacks. It runs
only on nodes that actually declare a repository-backed module.

The repository's `InstallationPolicy` is deliberately left alone:
`Install-Module -Force` suppresses the untrusted-repository prompt without
mutating machine-wide PowerShellGet configuration.

### Manifest regeneration

Manifest regeneration is centralized in one refresh-only `Exec` **per in-house
module** (`Exec["windowspowershell update-manifest ${modulename}"]`), declared
by `windowspowershell::module`. Every script notifies the Exec of the
module it belongs to, and Puppet refreshes a resource once per transaction
regardless of how many notifiers fire -- so changing ten scripts of the same
module in one run rebuilds its manifest once, not ten times. Two in-house
modules are entirely independent: changing a script in one never touches the
other's manifest.

### File unblocking

Files are unblocked at **deploy time**, not on every import. One refresh-only
`Exec` per module (`Exec["windowspowershell unblock-files ${modulename}"]`)
runs `Get-ChildItem -Recurse -File | Unblock-File` over that module's tree,
notified by its root module file and by every script that targets it -- so,
like the manifest regeneration, it runs at most once per transaction and only
when a file actually changes. The root module (`rootmodule.psm1`) therefore
does no per-session unblocking: unblocking is a deployment concern, and doing
it on every import walked the whole tree on each PowerShell session that
loaded the module.

### Configuration

`data/common.yaml` ships no override: every parameter already has a working,
neutral default. It is kept only as an extension point for a consuming
control-repo that wants to layer its own module-data defaults. The module data
layer is for module *defaults*, not site decisions -- `hiera.yaml` therefore
has a single `common` layer and no per-environment layer.

The `manage_pwsh_profile` parameter is left `undef` by default, which means
"manage the PowerShell 7 profile only where PowerShell 7 is installed". Opting a
whole agent environment in or out -- e.g. setting it to `false` for workstations
-- is a **site decision and belongs in the control-repo's Hiera**, at its
environment layer, not in this module. Varying it per environment from inside
the module would also be unreliable: `%{facts.agent_specified_environment}` is
only set when the agent explicitly requests an environment (`environment=` in
`puppet.conf` or `--environment`), so nodes classified by an ENC or by the
server lack the fact and the override is silently ignored.

### Facts

The module ships one custom fact and relies on one external fact:

- **`powershell7`** (shipped by this module, `lib/facter/powershell7.rb`) -- a
  structured fact `{ installed => Boolean, path => String }`. It detects
  PowerShell 7 by the presence of `pwsh.exe` on disk
  (`%ProgramFiles%\PowerShell\7\pwsh.exe`), which is what the managed profile
  actually needs -- unlike the package inventory, this also catches ZIP,
  Microsoft Store, winget and non-standard installs. `manage_pwsh_profile` left
  `undef` follows this fact. Forcing it `true` on a node without PowerShell 7
  fails the catalogue with an explicit message rather than writing a profile
  into a directory that does not exist.
- **`proxy`** (class parameter -- **not** a fact) --
  Proxy passed to `Install-Module` via the `$proxy` class parameter.
  Supports URLs with authentication (e.g. 'http://user:pass@proxy.example.net:3128').
  Set it in Hiera or node definition; if `undef`, installations go out directly.
  This parameter replaces the external `http_proxy` fact; the module no longer reads any site-provided structured fact for proxy detection.

## Reference

See [REFERENCE.md](REFERENCE.md), generated with
`bundle exec rake strings:generate:reference`.

## Limitations

- Windows only. On any other operating system the class **and every defined
  type** are a no-op, so nodes can be classified without filtering on the
  operating system. Parameter validation still runs everywhere, so a bad
  `scriptname` or a missing `content` fails the catalogue on Linux too.
- The parent of `module_root` must already exist.
- Requires `puppetlabs/powershell` for the `powershell` Exec provider,
  `puppetlabs/stdlib`, and `puppetlabs/concat` for the profile fragments.
- Version purging (`windowspowershell::external_module`) works on the versioned
  directory layout (`Modules\\<Name>\\<Version>\\`). A module installed the old
  flat way, with its files directly under `Modules\\<Name>\\`, is left alone.
- Third-party module management is confined to the **AllUsers** scope in the
  **64-bit** path (`C:\Program Files\WindowsPowerShell\Modules`). Copies under a
  user profile's `Documents\WindowsPowerShell\Modules`, `System32`, PowerShell
  7's own module directory, or the 32-bit `Program Files (x86)` tree are neither
  checked for idempotency nor purged.
- Relies on two facts (see [Facts](#facts)): the module-shipped `powershell7`
  custom fact, which `manage_pwsh_profile` follows when left `undef`.
