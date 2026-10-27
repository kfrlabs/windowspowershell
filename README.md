# windowspowershell

[![CI](https://github.com/kfrlabs/windowspowershell/actions/workflows/ci.yml/badge.svg)](https://github.com/kfrlabs/windowspowershell/actions/workflows/ci.yml)
[![Release to the Puppet Forge](https://github.com/kfrlabs/windowspowershell/actions/workflows/release.yml/badge.svg)](https://github.com/kfrlabs/windowspowershell/actions/workflows/release.yml)
[![Puppet Forge version](https://img.shields.io/puppetforge/v/kfrlabs/windowspowershell.svg)](https://forge.puppet.com/modules/kfrlabs/windowspowershell)
[![Puppet Forge downloads](https://img.shields.io/puppetforge/dt/kfrlabs/windowspowershell.svg)](https://forge.puppet.com/modules/kfrlabs/windowspowershell)
[![License: Apache-2.0](https://img.shields.io/github/license/kfrlabs/windowspowershell.svg)](LICENSE)
[![Puppet >= 8.0, < 9.0](https://img.shields.io/badge/puppet-%3E%3D8.0_%3C9.0-blue.svg)](metadata.json)
[![PDK 3.4.0](https://img.shields.io/badge/PDK-3.4.0-orange.svg)](https://puppet.com/docs/pdk/latest/pdk.html)
[![Windows 2019–2025, 11](https://img.shields.io/badge/windows-2019--2025_%7C_11-0078D6.svg?logo=windows)](metadata.json)

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

The module exposes one class and three defined types. Every defined type is
ensurable, so adding and retiring something is the same resource with a
different `ensure`.

```puppet
include windowspowershell
```

### Upgrading to 2.0

Checklist when coming from 1.x (details in [CHANGELOG.md](CHANGELOG.md#200---2026-10-22)):

- `import_in_profile` now defaults to `false` (issue #69): set it `true`
  explicitly where aliases/variables must be available at startup.
- Declare every in-house module explicitly (issue #46): `script` no longer
  creates its module, and `purge_versions` (default `true`, issue #29) cleans
  old version folders.
- Expect one manifest regeneration (issues #45, #28): the witness file makes
  `author`/`companyname`/`version`/GUID changes converge, and the GUID becomes
  name-derived once.
- Puppet 7 and Windows Server 2016 are dropped (issues #72, #70): run Puppet 8
  on a supported release.
- `proxy` URLs with userinfo and `scriptname` ending in `.ps1`/`.psm1` fail
  on parameter typing (issues #57, #56): move credentials to
  `proxy_credential`.
- Roll out in rings: pilot new nodes with the defaults before opting in
  (see [Production rollout](#production-rollout)).

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

To retire an in-house module that is no longer shipped, declare it absent
and retire its scripts first (a present script targeting an absent module
fails compilation, so the catalogue tells you which ones are left):

```puppet
windowspowershell::module { 'Acme':
  ensure => absent,
}

windowspowershell::script { 'Get-DiskUsage':
  modulename => 'Acme',
  ensure     => absent,
}
```

`ensure => absent` removes the whole module tree under the machine-wide
module directory (every version folder) and drops its `Import-Module` line
from the managed profiles on the next run. In-house modules are never
registered with PowerShellGet, so unlike the third-party `ensure => absent`
below there is no `Uninstall-Module` step.

In-house modules must never carry a protected system name: declaring
`windowspowershell::module { 'PowerShellGet': }` (or `'PackageManagement'`,
any case) fails compilation whatever `ensure` is, and
`windowspowershell::external_module` refuses those two names with
`ensure => absent` (issue #88). Overwriting or deleting them breaks
`Install-Module` for every later run. The refuse-list is deliberately
minimal -- only the two modules the package provider itself needs -- and
documented here rather than hidden in code: anything else under the
machine-wide directory (user-installed third-party modules, stale copies)
stays manageable, at the operator's own risk.

#### Importing the module from the profile

By default (`import_in_profile => false`) the module is not imported by the
machine-wide profiles: it lives under the machine-wide module directory,
which for the default root is part of `PSModulePath`, and its manifest
exports each function by
name, so PowerShell discovers and loads it on first use of one of its
functions, without paying the load cost at every session startup. A custom
`module_root` is not on `PSModulePath`, so auto-loading is broken there:
set `import_in_profile => true` with managed profiles, or handle
`PSModulePath` explicitly (see [Limitations](#limitations), issue #110).
`import_in_profile => true` repairs in-house imports (absolute manifest
path); external `source`-backend modules on a custom root still need
explicit `PSModulePath` handling.

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

> **Repository backend requires the default `module_root`** (issue #85):
> `Install-Module -Scope AllUsers` always installs to
> `C:\Program Files\WindowsPowerShell\Modules` and ignores a custom root,
> so combining `repository` with a custom `module_root` fails compilation
> instead of reinstalling on every run. Use the `source` backend for a
> custom root. A custom root is also off `PSModulePath` and gets no ACL
> from this module (see [Limitations](#limitations), issue #110).

A custom repository must be registered for the `SYSTEM` account (issue #85):
`Register-PSRepository` is per-user, so a repository registered in an
interactive session is invisible to the agent and `Install-Module` fails
with "Unable to find repository". Register it from a Scheduled Task as
SYSTEM (or the account running the agent) on every node that uses it, before
the first agent run. See `tools/Test-RepositoryBackend.ps1` for a
self-contained local file repository example.

`ensure => present` is install-once: it installs the newest version only when
none is present and never upgrades an already-installed one on later runs. To
move a node to a newer version, pin that version in `ensure`. An interrupted
install may leave an empty or partial version folder behind: such a folder
does not count as installed (its `<modulename>.psd1` must exist and pass
`Test-ModuleManifest`), so the next run reinstalls and repairs it.

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
These paths describe the default root: with a custom `module_root` the
`source` backend acts on that root instead, which is not on `PSModulePath`
(auto-loading broken unless `import_in_profile => true` with managed
profiles, or explicit `PSModulePath` handling) and gets no ACL from this
module (see [Limitations](#limitations), issue #110). `import_in_profile
=> true` repairs in-house imports (absolute manifest path); external
`source`-backend modules on a custom root still need explicit
`PSModulePath` handling.

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
appears in the `command` or `unless` text.

Validated end to end as SYSTEM against the real Gallery through a local
authenticating CONNECT proxy (issue #85, `tools/Test-ProxyBackend.ps1`):
`Find-Module` (same PackageManagement download path as `Install-Module`)
succeeds with good credentials on Windows Server 2025. A file:// repository
ignores `-Proxy` (expected: no HTTP involved), which is why the repository
integration test stays offline and proxy coverage lives in the dedicated
proxy script. The `environment` of the `Exec` is
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

### Execution cost per run (issue #92)

In steady state (nothing to change), each managed module costs one
PowerShell spawn per run: the `unless` guard of its version-purge `Exec`
(`windowspowershell::module` and the `source` backend of
`windowspowershell::external_module`). A repository-backed external module
costs two (install check plus purge check). Measured on Windows Server 2025
(Puppet 8.31, agent as SYSTEM): ~0.65 s per module (~1.5 s once per run for
the first, cold spawn; ~0.6 s each after that).

| In-house modules | Stable run, total | Of which purge checks |
|---|---|---|
| 1 | ~34 s | ~1.5 s |
| 10 | ~40 s | ~7 s |
| 30 | ~54 s | ~20 s |

The run total is dominated by a fixed Puppet overhead (~30 s of fact
collection on the measured node plus catalog compilation), not by this
module: up to about fifteen modules the extra cost disappears in the noise.
Past that, budget roughly 0.65 s per module per run. If a module's versions
are guaranteed unique (a single `external_module` per name, no side-by-side
copies), `purge_versions => false` drops its per-run cost to zero. On top of
the per-module checks, every run also evaluates the `module_root` parent
guard of `windowspowershell::install` (issue #96): one `unless` spawn per
run (~0.6 s), whether or not anything is managed. With a custom
`module_root`, see also the `PSModulePath`/ACL caveats in
[Limitations](#limitations) (issue #110).

### Co-managing the profiles

> Opt-in (issue #109): `manage_profiles` defaults to `false`, so no profile
> is managed until the site opts in with `manage_profiles => true`.
> Managing is destructive by design (issue #90): from the first run each
> managed profile is rebuilt from its fragments without a backup. Inventory
> and back up any existing profile content before the first run, and pilot
> new nodes with the default `false` before opting in.

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
- To manage the profiles entirely from your own code instead, leave
  `manage_profiles => false` (the default). The class then declares no profile at all and
  `profile_paths` is empty. This is also the recommended pilot path: start
  with the default, inventory existing profile content, move what must survive
  into a fragment, then opt in with `manage_profiles => true`.
- Content that Puppet does not manage (a GPO startup script writing to the
  profile, an administrator editing it) is **not** preserved and is removed
  without a backup from the first run. Move it into a
  fragment, or keep it out of these files.

### Production rollout

Roll out in rings (issue #108): pilot on Windows Server 2022 and 2025
first, then the rest of the fleet. Windows Server 2019 and Windows 11 are
supported but lab-unvalidated (issue #87, see the manual matrix in
[TESTING.md](TESTING.md#manual-matrix)): treat them as their own later ring
and verify the double-apply there before widening.

Pilot with the safe defaults: keep `manage_profiles` at its `false`
default, keep `import_in_profile => false` on every module, and review
`purge_versions` (default `true`) only where side-by-side versions are
genuinely needed:

```yaml
# Pilot ring: stay on the defaults, opt in per-module only where needed
windowspowershell::manage_profiles: false
```

Opt in to managed profiles only after the pre-flight inventory below, one
ring at a time (`windowspowershell::manage_profiles: true`).

Pre-flight inventory, per node, before the first managed run. The module
makes no backup: copy anything worth keeping off the node first.

```powershell
Get-Content C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1 -ErrorAction SilentlyContinue
Get-Content C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1 -ErrorAction SilentlyContinue
# Only where PowerShell 7 is installed at its default location:
Get-Content 'C:\Program Files\PowerShell\7\profile.ps1' -ErrorAction SilentlyContinue
Get-ChildItem 'C:\Program Files\WindowsPowerShell\Modules'
```

With a custom `module_root`, inventory that directory instead of the
default path above. It is not on `PSModulePath` (auto-loading broken
unless `import_in_profile => true` with managed profiles, or explicit
`PSModulePath` handling) and it gets no ACL from this module (see
[Limitations](#limitations), issue #110). `import_in_profile => true`
repairs in-house imports (absolute manifest path); external
`source`-backend modules on a custom root still need explicit
`PSModulePath` handling.

Move the profile content that must survive into a `concat::fragment`
(see [Co-managing the profiles](#co-managing-the-profiles)) before opting
in; content left outside a fragment is removed without a backup from the
first managed run.

To retire an in-house module safely, retire its scripts first, then the
module (script first, then module -- reverse of display order above):

```puppet
windowspowershell::script { 'Get-OldThing':
  modulename => 'Acme',
  ensure     => absent,
}

windowspowershell::module { 'Acme':
  ensure => absent,
}
```

Retiring removes the module tree (every version folder) and drops its
`Import-Module` line from the managed profiles on the next run. It does
not restore anything: the previous profile content is not put back, and
the removed version folders are not reinstalled. A `script` with
`ensure => present` naming an absent module fails compilation (issue #88),
so the catalogue tells you which scripts are left behind -- retire those
first.

Rollback of profile management: setting `manage_profiles` back to `false`
declares no `concat` target at all (`$profile_paths` becomes empty in
`init.pp`, and `windowspowershell::config` only declares the targets when
it is `true`), so Puppet stops managing the files and leaves them on disk
exactly as last written. To clean up, either delete the left-over
`profile.ps1` files by hand (after backing up anything still needed) or
set `manage_profiles => true` again to bring them back under management.
If you added fragments with literal targets, remove or conditionalize them;
the `$profile_paths.each` pattern above needs no change (it declares nothing
when empty).

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

Profile management itself is opt-in: `manage_profiles` defaults to `false`,
so no profile is managed until the site opts in, e.g. in Hiera:

```yaml
windowspowershell::manage_profiles: true
```

`import_in_profile => true` on a module only adds its `Import-Module` line
once profiles are managed.

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

### Troubleshooting

#### `module_root` parent does not exist (issue #96)

A custom `module_root` whose parent directory does not exist on the node
fails the run before anything is deployed:

```text
Error: .../Exec[windowspowershell module_root parent exists]/returns:
change from 'notrun' to ['0'] failed: 'throw 'windowspowershell:
module_root ''C:\wps-perf\Modules1'' was not created: parent directory
''C:\wps-perf'' does not exist. ...''' ...
Notice: .../File[C:\wps-perf\Modules1]: Dependency Exec[windowspowershell
module_root parent exists] has failures: true
Warning: .../File[C:\wps-perf\Modules1]: Skipping because of failed dependencies
```

With `--detailed-exitcodes` the run reports failure (exit 4 when nothing
else changed), and every resource depending on `module_root` is skipped.
This is the guard in `windowspowershell::install` failing fast with an
explicit message, instead of the file provider's generic `parent directory
... does not exist` further down the run.

Fix: create the parent on the node (`New-Item -ItemType Directory -Path
C:\wps-perf`), or fix the typo in `module_root`. The module deliberately
does not create missing parents: silently growing an arbitrary tree as
SYSTEM would turn a typo into a green run deploying modules where
PowerShell never looks.

A custom `module_root` that does exist is still not on `PSModulePath`
(auto-loading broken: use `import_in_profile => true` with managed
profiles, or handle `PSModulePath` explicitly) and gets no ACL from this
module (it inherits the parent's; see [Limitations](#limitations),
issue #110). `import_in_profile => true` repairs in-house imports
(absolute manifest path); external `source`-backend modules on a custom
root still need explicit `PSModulePath` handling.

## Reference

See [REFERENCE.md](REFERENCE.md), generated with
`bundle exec rake strings:generate:reference`.

## Development

See [TESTING.md](TESTING.md) for how the module is tested (rspec-puppet, parsing and
PSScriptAnalyzer of the generated PowerShell, Windows runtime smoke test) and for
the manual Windows validation matrix.

A `v*.*.*` tag only publishes to the Forge when CI is green on that commit:
`release.yml` gates the publish on the `Test suite` check from `ci.yml`
(see [Release gate](TESTING.md#release-gate)).

Contributions are welcome via GitHub issues and pull requests.

## Limitations

- Supported releases are Windows Server 2019–2025 and Windows 11 (see
  `metadata.json`). Windows Server 2016 is not supported. Windows Server 2019
  is claimed but still to be tested/confirmed (issue #87); see `TESTING.md`.
- Windows only. On any other operating system the class **and every defined
  type** are a no-op, so nodes can be classified without filtering on the
  operating system. Parameter validation still runs everywhere, so a bad
  `scriptname` or a missing `content` fails the catalogue on Linux too.
- The parent of `module_root` must already exist: the module manages the
  directory itself but never creates missing parents (a typo would otherwise
  turn into a green run deploying where PowerShell never looks). A missing
  parent fails the run early with an explicit message naming `module_root`
  and the parent (issue #96); see [Troubleshooting](#troubleshooting).
- A trailing separator in `module_root` (`C:\Modules\`) is allowed and
  stripped once for every derived path (issue #111): the class exposes the
  stripped form as `$windowspowershell::normalized_module_root`, so manifests
  list relative `NestedModules` with or without it. Nodes first converged
  with a trailing-separator root regenerate their in-house manifests once
  (the witness hash follows the manifest command), with no content change
  beyond the path prefix.
- A custom `module_root` is not on `PSModulePath`, so module auto-loading
  is broken there (issue #110): the default root is discovered on first
  use, a custom root is not. Set `import_in_profile => true` with managed
  profiles, or handle `PSModulePath` explicitly. `import_in_profile => true`
  repairs in-house imports (absolute manifest path); external `source`-backend
  modules on a custom root still need explicit `PSModulePath` handling. Managing
  the machine-wide
  `PSModulePath` from the module was considered and deferred: it mutates
  machine environment persistently, globally and order-sensitively, which
  does not fit this module's safe-default posture.
- The module applies no ACL to `module_root`: the directory inherits its
  parent's ACL, so a custom root writable by non-administrators lets any
  writer plant code the agent then runs as SYSTEM (privilege escalation,
  issue #110). Restrict the directory to `SYSTEM` and `Administrators`
  with Full control and verify with `Get-Acl`. Enforcing the ACL from the
  module was considered and deferred: it needs a new ACL dependency (or
  `icacls` as SYSTEM), is heavy, and requires Windows validation -- docs
  warning only for now.
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
- The machine-wide profiles are managed only when `manage_profiles => true`
  (default `false`, opt-in): each managed profile is replaced wholesale on
  each run, and only content
  coming from a `concat::fragment` survives. Puppet code can add its own
  fragments (see [Co-managing the profiles](#co-managing-the-profiles)), but
  lines written by a GPO startup script, another tool or an administrator are
  removed. Managing only a delimited block of the file is not supported.
- Non-ASCII module names, script names and script content are not supported
  where Windows PowerShell 5.1 runs the agent (issue #89): the files Puppet
  writes are UTF-8 without a BOM, which 5.1 reads as ANSI, so e.g.
  `Café-Tools` converges (the double apply is clean) but the deployed
  function is unreachable under its real name. Keep names and content
  ASCII-only where 5.1 may run; files deployed from a `source` must be saved
  accordingly (UTF-8 with BOM also works, PowerShell 7 reads BOM-less UTF-8
  fine). Verified on Windows Server 2025, see `TESTING.md`.
- A syntactically broken `Functions/` script fails the manifest build without
  touching the existing `.psd1` (fail-closed, issue #107): every script is
  parsed (syntax only, read as UTF-8) before `New-ModuleManifest` runs, and a
  `PARSE ERROR <file>:<line>` names the culprit. Anything beyond syntax (a
  missing command, a wrong export list) is not checked.
