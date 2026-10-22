# windowspowershell

[![CI](https://github.com/kfrlabs/windowspowershell/actions/workflows/ci.yml/badge.svg)](https://github.com/kfrlabs/windowspowershell/actions/workflows/ci.yml)
[![Release to the Puppet Forge](https://github.com/kfrlabs/windowspowershell/actions/workflows/release.yml/badge.svg)](https://github.com/kfrlabs/windowspowershell/actions/workflows/release.yml)
[![Puppet Forge version](https://img.shields.io/puppetforge/v/kfrlabs/windowspowershell.svg)](https://forge.puppet.com/modules/kfrlabs/windowspowershell)
[![Puppet Forge downloads](https://img.shields.io/puppetforge/dt/kfrlabs/windowspowershell.svg)](https://forge.puppet.com/modules/kfrlabs/windowspowershell)
[![License: Apache-2.0](https://img.shields.io/github/license/kfrlabs/windowspowershell.svg)](LICENSE)
[![Puppet >= 8.0, < 9.0](https://img.shields.io/badge/puppet-%3E%3D8.0_%3C9.0-blue.svg)](metadata.json)
[![PDK 3.4.0](https://img.shields.io/badge/PDK-3.4.0-orange.svg)](https://puppet.com/docs/pdk/latest/pdk.html)
[![Windows 2019–2025, 10/11](https://img.shields.io/badge/windows-2019--2025_%7C_10%2F11-0078D6.svg?logo=windows)](metadata.json)

## Table of Contents

1. [Description](#description)
2. [Usage](#usage)
3. [Reference](#reference)
4. [Limitations](#limitations)
5. [Development](#development)

## Description

Builds custom, per-node PowerShell modules from Puppet sources on Windows nodes:

- one or more **in-house PowerShell modules**, assembled dynamically from
  `.ps1` scripts deployed by Puppet (`content` / `source`, `puppet:///`),
  with its manifest (`.psd1`) regenerated automatically. Classification and
  Hiera decide which scripts land on which node, so two nodes can build two
  different contents under the same module name;
- the machine-wide profiles (Windows PowerShell 5.1 and PowerShell 7);
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

One resource is one module identity. Every module has to be declared: a
`windowspowershell::script` does not create the module it names, it fails to
compile when that module is missing. `windowspowershell::module { 'Acme': }`
is enough to get every default; add `version`, `companyname` or `author` only
to override one.

```puppet
windowspowershell::module { 'Acme':
  version     => '1.2',
  companyname => 'Acme Corp',
  author      => 'Platform Team',
}
```

`version` requires at least two dot-separated components (e.g. `'1.2'`): a
single number such as `'1'` is refused at compile time, because PowerShell
casts `-ModuleVersion` to `[version]`. See the breaking-change note under
[1.2.0] in [CHANGELOG.md](CHANGELOG.md).

#### Importing the module from the profile

By default (`import_in_profile => false`) the module is not imported by the
machine-wide profiles: it lives under the machine-wide module directory,
which is part of `PSModulePath`, and its manifest exports each function by
name, so PowerShell discovers and loads it on first use of one of its
functions, without paying the load cost at every session startup.

Set `import_in_profile => true` when the session needs something module
auto-loading does not provide up front, typically the aliases or variables
the module defines (the manifest exports them with a wildcard, which
auto-loading does not use to discover them), or when a function must already
be loaded at startup.

> **Breaking change in 2.0.0** (issue #69): the default was `true` before.
> Every session paid the import cost unless the site opted out. After the
> upgrade, nodes that relied on the profile import (aliases/variables
> available at startup) must set `import_in_profile => true` explicitly.

If the import fails (a broken module, a missing file), the profile prints a
warning with the reason at the start of the session instead of failing
silently. The session itself keeps starting normally.

### Scripts: `windowspowershell::script`

A script becomes a function of the in-house module named in `modulename`,
which is mandatory: there is no default module to fall back to. The resource
title is the function name.

```puppet
# The module the scripts go into has to be declared (see below)
windowspowershell::module { 'Acme': }

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

The module named by `modulename` has to be declared with
`windowspowershell::module`; a script does not create it. A script naming an
undeclared module fails to compile with a message that names the module and
says where to declare it. Add `version`, `companyname` or `author` to the
module only to override a default.

Declaration order does not matter within one class or manifest: Puppet
evaluates the body of a script after the scope that declared it, so the module
can be written before or after the scripts. It matters across scopes. If the
module is declared from a scope evaluated *after* a script's body (for
instance from a define nested deeper than the script), the script cannot see
it yet and fails with the same message. Declare the module from a class
evaluated before the one declaring the scripts.

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

Declare one `external_module` resource per module name. Two resources sharing
a `modulename` under different titles each purge the other side's version, so
with different versions the node reinstalls on every run and never converges.
Sharing is only supported with `purge_versions => false` on all but one side,
and only with the `repository` backend: with the `source` backend both titles
declare the same versioned directory, which fails the catalogue with a
duplicate resource.

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

The class does that from the `$proxy` parameter. Nodes without that parameter go out directly.

> **Breaking change in 1.1.0** (issue #18): the module no longer reads the
> site-provided `http_proxy` structured fact. Set the proxy explicitly in
> Hiera (`windowspowershell::proxy: 'http://proxy.example.net:3128'`);
> `undef` means direct. See the 1.1.0 proxy note under [1.2.0] in
> [CHANGELOG.md](CHANGELOG.md).

For a proxy that requires authentication, keep the endpoint in `proxy` and pass
the credentials separately in `proxy_credential`, with a `Sensitive` password:

```puppet
class { 'windowspowershell':
  proxy            => 'http://proxy.example.net:3128',
  proxy_credential => {
    username => 'svc-puppet',
    password => Sensitive('s3cret'),
  },
}
```

The credentials reach `Install-Module` and `Install-PackageProvider` through
`-ProxyCredential`. The script reads them from the `WPS_PROXY_USER` and
`WPS_PROXY_PASSWORD` environment variables of the `Exec`, so the secret never
appears in the `command` or `unless` text. The `environment` of the `Exec` is
wrapped in `Sensitive`, which keeps it out of Puppet reports and logs. It still
reaches the agent inside the catalog, as for any secret an agent has to use.

A hash cannot carry a `Sensitive` value straight from Hiera. Wrap the secret in
Puppet code instead, e.g. in a profile:

```puppet
class { 'windowspowershell':
  proxy            => lookup('profile::proxy::url'),
  proxy_credential => {
    username => lookup('profile::proxy::username'),
    password => Sensitive(lookup('profile::proxy::password')),
  },
}
```

> **Breaking change in 2.0.0** (issue #57): credentials embedded in the
> proxy URL (`http://user:pass@host`) are refused at compile time. They ended
> up in clear text in the `Exec` command and .NET may not honor them. Move
> them to `proxy_credential`.

#### Bootstrap

Installing from a repository pulls in `windowspowershell::psget`, which
installs the NuGet package provider when it is missing on the node. It runs
only on nodes that actually declare a repository-backed module.

The repository's `InstallationPolicy` is deliberately left alone:
`Install-Module -Force` suppresses the untrusted-repository prompt without
mutating machine-wide PowerShellGet configuration.

#### Repository trust

`Install-Module` runs with `-Force -AllowClobber` as `SYSTEM` (the account of
the Puppet agent). A PowerShell module can run arbitrary code, both when it is
installed and when it is imported, and `-Force` removes the usual untrusted
repository prompt. Whichever repository you name in `repository` is therefore
**trusted to execute code as `SYSTEM` on every node that declares the
resource**, with a pinned version only guaranteeing you get the release you
asked for from that source, not that the source is trustworthy.

For production, point `repository` at an internal mirror or feed that you
control and that only carries reviewed modules, rather than at the public
PowerShell Gallery. For nodes that cannot, or should not, reach any repository,
use the `source` backend and ship the module files from your Puppet code.

### Manifest regeneration

Manifest regeneration is centralized in one refresh-only `Exec` **per in-house
module** (`Exec["windowspowershell update-manifest ${modulename}"]`), declared
by `windowspowershell::module`. Every script notifies the Exec of the
module it belongs to, and Puppet refreshes a resource once per transaction
regardless of how many notifiers fire -- so changing ten scripts of the same
module in one run rebuilds its manifest once, not ten times. Two in-house
modules are entirely independent: changing a script in one never touches the
other's manifest.

Changing a manifest parameter on its own (`author`, `companyname`, `version`)
regenerates the manifest too: a refresh-only `Exec` does not run when its own
`command` changes, so `windowspowershell::module` also manages a witness file,
`<version folder>\.manifest-params`, holding the SHA-256 of the manifest build
command. When that hash changes, the file changes and notifies the same
`Exec`. Do not edit or remove the witness by hand; if you do, Puppet rewrites
it and rebuilds the manifest on the next run. A `.psd1` that is corrupt or
edited by hand while the witness is intact is not detected: delete the `.psd1`
to have it rebuilt.

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

### Co-managing the profiles

The machine-wide profiles (`System32`, `SysWOW64` and, when managed, PowerShell
7) are `concat` resources owned by this module: on every run the file is
rebuilt from its fragments, so **anything in it that does not come from a
`concat::fragment` is removed**. That includes lines added by hand, by a GPO
startup script or by a tool outside Puppet. Puppet code, however, can add its
own content: declare a `concat::fragment` whose `target` is one of the paths in
`$windowspowershell::profile_paths`, and it is assembled with the rest.

| Order       | Owner                                                          |
|-------------|----------------------------------------------------------------|
| `00`        | Header, declared by this module                                |
| `01`-`49`   | Free: your content, before the module imports                  |
| `50`        | `Import-Module` lines of in-house modules (`windowspowershell::module`) |
| `60`        | `Import-Module` lines of external modules (`windowspowershell::external_module`) |
| `70`-`99`   | Free: your content, after the module imports                   |

The target names are the profile paths themselves:

- `C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1`
- `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1`
- `C:\Program Files\PowerShell\7\profile.ps1` (only when the PowerShell 7
  profile is managed, see `manage_pwsh_profile`)

`$windowspowershell::profile_paths` is the exact list of managed paths for the
node (empty when `manage_profiles => false`), so iterating over it keeps your
fragment in step with the class parameters:

```puppet
include windowspowershell

# Declared only where the class declares the concat targets: on any other
# operating system the targets do not exist and the fragment would fail to
# compile.
if $windowspowershell::supported {
  $windowspowershell::profile_paths.each |$profile_path| {
    concat::fragment { "acme profile extras in ${profile_path}":
      target  => $profile_path,
      order   => '70',
      content => "Set-Alias ll Get-ChildItem\n",
    }
  }
}
```

Keep these points in mind:

- Fragment titles must be unique across the catalogue; include the profile
  path in the title when you declare one fragment per profile, as above.
- Each fragment's `content` should end with a newline: `concat` joins
  fragments as they are.
- To manage the profiles entirely from your own code instead, set
  `manage_profiles => false`. The class then declares no profile at all and
  `profile_paths` is empty.
- Content that Puppet does not manage (a GPO startup script writing to the
  profile, an administrator editing it) is **not** preserved. Move it into a
  fragment, or keep it out of these files.

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

The module ships one custom fact:

- **`powershell7`** (shipped by this module, `lib/facter/powershell7.rb`) -- a
  structured fact `{ installed => Boolean, path => String }`. It detects
  PowerShell 7 by the presence of `pwsh.exe` at its **default location only**
  (`%ProgramFiles%\PowerShell\7\pwsh.exe`, where the MSI package installs it). That is deliberate: the managed profile is
  `C:\Program Files\PowerShell\7\profile.ps1`, and PowerShell only loads a
  machine-wide profile from its own install directory. A ZIP install elsewhere,
  a Microsoft Store install (read-only `WindowsApps`) or a 32-bit install is
  therefore **not detected** (`installed => false`), and the module does not
  manage a profile for it. `manage_pwsh_profile` left `undef` follows this
  fact. Forcing it `true` on a node without PowerShell 7 at the default
  location fails the catalogue with an explicit message rather than writing a
  profile into a directory that does not exist.

`proxy` and `proxy_credential` are class parameters, not facts: see
[Proxy](#proxy).

## Reference

See [REFERENCE.md](REFERENCE.md), generated with
`bundle exec rake strings:generate:reference`.

## Development

See [TESTING.md](TESTING.md) for how the module is tested (rspec-puppet, parsing and
PSScriptAnalyzer of the generated PowerShell, Windows runtime smoke test) and for
the manual Windows validation matrix.

Contributions are welcome via GitHub issues and pull requests.

## Limitations

- Supported releases are Windows Server 2019–2025 and Windows 10/11 (see
  `metadata.json`). Windows Server 2016 is not supported. Windows Server 2019
  is claimed but still to be tested/confirmed (issue #70); see `TESTING.md`.
- Windows only. On any other operating system the class **and every defined
  type** are a no-op, so nodes can be classified without filtering on the
  operating system. Parameter validation still runs everywhere, so a bad
  `scriptname` or a missing `content` fails the catalogue on Linux too.
- The parent of `module_root` must already exist.
- Requires `puppetlabs/powershell` for the `powershell` Exec provider,
  `puppetlabs/stdlib`, and `puppetlabs/concat` for the profile fragments.
- Version purging (`windowspowershell::external_module`) works on the versioned
  directory layout (`Modules\<Name>\<Version>\`). A module installed the old
  flat way, with its files directly under `Modules\<Name>\`, is left alone.
- Third-party module management is confined to the **AllUsers** scope in the
  **64-bit** path (`C:\Program Files\WindowsPowerShell\Modules`). Copies under a
  user profile's `Documents\WindowsPowerShell\Modules`, `System32`, PowerShell
  7's own module directory, or the 32-bit `Program Files (x86)` tree are neither
  checked for idempotency nor purged.
- Relies on one fact (see [Facts](#facts)): the module-shipped `powershell7`
  custom fact, which `manage_pwsh_profile` follows when left `undef`. It only
  sees PowerShell 7 at its default location
  (`C:\Program Files\PowerShell\7`); ZIP, Microsoft Store and 32-bit installs
  elsewhere get no managed pwsh profile.
- The machine-wide profiles are replaced wholesale on each run: only content
  coming from a `concat::fragment` survives. Puppet code can add its own
  fragments (see [Co-managing the profiles](#co-managing-the-profiles)), but
  lines written by a GPO startup script, another tool or an administrator are
  removed. Managing only a delimited block of the file is not supported.
