# @summary Builds custom per-node PowerShell modules from Puppet sources and manages profiles.
#
# This class owns every *site-wide* path and setting. It does **not** own an
# in-house module identity any more: a site can build as many in-house
# modules as it wants, each declared with `windowspowershell::module`
# (title = the module name) and populated with
# `windowspowershell::script { ... modulename => '<that title>' }`. There is
# no module-wide default module name: each `windowspowershell::script` has to
# say which in-house module it belongs to.
#
# On a non-Windows node the whole module is a no-op, including both defined
# types, so it is safe to classify nodes without filtering on the operating
# system.
#
# @param module_root
#   Machine-wide PowerShell module directory, shared by every in-house
#   module this class lays out and by `windowspowershell::external_module`
#   with the `source` backend. The `repository` backend always installs
#   with `Install-Module -Scope AllUsers` to
#   `C:\Program Files\WindowsPowerShell\Modules` and ignores a custom root
#   (issue #85): combining `repository` with a custom `module_root` fails
#   compilation. The module manages this directory itself (via ensure_resource,
#   so it can be co-managed by another module), but it never creates missing
#   parents: when the parent directory does not exist on the node, the run
#   fails early with a message naming `module_root` and the missing parent
#   (issue #96) instead of the file provider's generic error. Create the
#   parent on the node before the run, or fix the typo. See
#   "Troubleshooting" in the README.
#   Trailing separators are allowed and stripped for every derived path
#   (`C:\Modules\` behaves like `C:\Modules`): the class exposes the
#   stripped form as `$windowspowershell::normalized_module_root`, which
#   every defined type builds its paths from (issue #111).
#   A custom root is not on `PSModulePath` (auto-loading broken: use
#   `import_in_profile => true` with managed profiles, or handle
#   `PSModulePath` explicitly) and gets no ACL from this module (it
#   inherits the parent's: restrict to SYSTEM + Administrators Full and
#   verify with `Get-Acl`). `import_in_profile => true` repairs in-house
#   imports (absolute manifest path); external `source`-backend modules on
#   a custom root still need explicit `PSModulePath` handling. With
#   `manage_module_root_acl => true` the module restricts a custom root to
#   `SYSTEM` + `Administrators` Full control instead of inheriting the
#   parent's ACL (opt-in, issue #133). See "Limitations" in the README
#   (issue #110).
# @param manage_profiles
#   Whether to manage the machine-wide PowerShell profiles. Defaults to
#   `false` (opt-in, issue #109): no profile is managed and
#   `$windowspowershell::profile_paths` is empty, so `import_in_profile => true`
#   on a module adds no `Import-Module` line anywhere until this is set `true`.
#   Each in-house module with `import_in_profile => true` adds its own
#   `Import-Module` line to these profiles; `windowspowershell::external_module` does
#   the same for a third-party module when `import_in_profile => true` is
#   passed to it.
#   Destructive by design (issue #90): set to `true`, and from the first
#   run the profile files are rebuilt from their fragments without a backup:
#   on every run, anything in them that does not come from a `concat::fragment`
#   targeting them is removed. Inventory and back up any existing profile
#   content before the first run, and pilot new nodes with the default
#   `false` before opting in with `manage_profiles => true`. Other
#   Puppet code can add its own content by declaring a `concat::fragment` with
#   `target` set to a path in `$windowspowershell::profile_paths` and an
#   `order` between `01` and `49` (before the module imports) or `70` and `99`
#   (after them); `00` is the header, `50` the in-house imports and `60` the
#   external imports. Lines added by a GPO startup script or by hand are not
#   preserved. See "Co-managing the profiles" in the README.
#   See "Production rollout" in the README for the ring order, the pre-flight
#   inventory and the rollback procedure (issue #108).
# @param manage_pwsh_profile
#   Whether to manage the PowerShell 7 profile. Left `undef`, it is managed
#   only on nodes where PowerShell 7 is installed at its default location
#   (`C:\Program Files\PowerShell\7\pwsh.exe`); a ZIP, Microsoft Store or
#   32-bit install elsewhere is not detected. Set it in Hiera to opt a
#   whole agent environment in or out.
# @param proxy
#   Proxy passed to `Install-Module` when installing a third-party module from
#   a repository. Left `undef`, no proxy is used and installs go out directly.
#   Set it to an explicit proxy URL (e.g. 'http://proxy.example.net:3128').
#   Credentials embedded in the URL (`http://user:pass@host`) are refused: they
#   ended up in clear text in the Exec command, and .NET may not honor them.
#   Pass them via `proxy_credential` instead.
# @param proxy_credential
#   Credentials for an authenticating proxy, as a hash with `username` and a
#   `Sensitive` `password`. Requires `proxy`. They are passed to
#   `Install-Module` and `Install-PackageProvider` through `-ProxyCredential`;
#   the secret travels in the Exec `environment` (redacted from reports and
#   logs) and never appears in the Exec `command` or `unless` text.
# @param manage_module_root_acl
#   Whether to harden a custom `module_root`'s ACL from this module
#   (opt-in, issue #133). The agent runs as SYSTEM and loads code from
#   `module_root`, so a custom root inheriting a parent ACL writable by
#   non-administrators is a privilege escalation path. With `true`, an
#   enforceable custom root is restricted to `SYSTEM` + `Administrators`
#   Full control (by SID, locale-independent), inheritance disabled; a
#   converged node changes nothing (one `unless` PowerShell spawn per run,
#   ~0.6 s, see "Execution cost per run" in the README). Defaults to
#   `false`: an opted-out custom root logs a compile-time warning naming
#   the root and this parameter instead (the warning goes to the Puppet
#   server log, not to the agent report). The default root is never
#   modified and never warns. UNC, extended-prefix (`\\?\`) and drive
#   roots are never enforced (setting `true` there logs a warning and
#   compiles without ACL resources): restrict those by hand. Pre-existing
#   content under the root keeps its old entries until recreated; content
#   deployed after the first hardened run inherits the two entries.
# @param path_length_policy
#   What to do when a `windowspowershell::module` or
#   `windowspowershell::script` with `ensure => present` manages a path
#   longer than 259 characters (Windows `MAX_PATH`, terminating NUL
#   included) on a node without long-path support, i.e. where the
#   `long_paths_enabled` fact is `false` or missing (issue #137).
#   `warn` (the default) logs a compile-time warning, `fail` fails
#   compilation instead, and `ignore` stays silent. On a node with
#   long-path support (fact is `true`) over-limit paths are legitimate and
#   nothing is logged, whatever this is set to. `ensure => absent`
#   resources are exempt. The fact is delivered by pluginsync, so the
#   first run after enabling it may still warn or fail before the agent
#   has the fact.
#
# @example Build an in-house module and deploy a script into it
#   include windowspowershell
#
#   windowspowershell::module { 'Acme':
#     version     => '1.2',
#     companyname => 'Acme Corp',
#     author      => 'Platform Team',
#   }
#
#   windowspowershell::script { 'Get-DiskUsage':
#     modulename => 'Acme',
#     content    => file('profile/powershell/Get-DiskUsage.ps1'),
#   }
#
# @example Install through an authenticating proxy
#   class { 'windowspowershell':
#     proxy            => 'http://proxy.example.net:3128',
#     proxy_credential => {
#       username => 'svc-puppet',
#       password => Sensitive('s3cret'),
#     },
#   }
#
# @example Deploy a third-party module
#   windowspowershell::external_module { 'PSWindowsUpdate':
#     ensure     => '2.2.1.5',
#     repository => 'PSGallery',
#   }
class windowspowershell (
  Windowspowershell::Rootpath $module_root = 'C:\Program Files\WindowsPowerShell\Modules',
  Boolean $manage_profiles = false,
  Optional[Boolean] $manage_pwsh_profile = undef,
  Optional[Windowspowershell::Proxyurl] $proxy = undef,
  Optional[Struct[{
        username => String[1],
        password => Sensitive[String[1]],
  }]] $proxy_credential = undef,
  Boolean $manage_module_root_acl = false,
  Enum['warn', 'fail', 'ignore'] $path_length_policy = 'warn',
) {
  # Whether this node gets any resources at all. Read by
  # windowspowershell::script, windowspowershell::module and
  # windowspowershell::external_module, which must no-op on the same nodes this class
  # does, so that node classification never has to filter on the operating
  # system.
  $supported = $facts['os']['family'] == 'windows'

  # Issue #111: a trailing separator in module_root (allowed by
  # Windowspowershell::Rootpath) used to leak a doubled separator into
  # every derived path (C:\Modules\Acme\1.0 built as C:\Modules\\Acme\1.0),
  # so the manifest template's Replace("${modulePath}\", '') missed and
  # NestedModules stayed absolute. Strip trailing separators once here and
  # build every path from the stripped form instead. Degenerate roots are
  # preserved: a bare drive (C: stripped from C:\) is re-anchored to its
  # root (C:\), an all-separator value falls back to module_root unchanged,
  # and forward slashes elsewhere are left alone (only the trailing run is
  # stripped).
  $stripped_module_root = regsubst($module_root, /[\/\\]+$/, '')
  $normalized_module_root = $stripped_module_root =~ /:$/ ? {
    true    => "${stripped_module_root}\\",
    default => $stripped_module_root == '' ? {
      true    => $module_root,
      default => $stripped_module_root,
    },
  }

  # Issue #133: opt-in ACL hardening of a custom module_root. Compared on
  # normalized forms (issue #111): slash-normalized, downcased and
  # trailing-stripped, so a trailing separator or a different case on the
  # default root neither enforces nor warns spuriously (same normalization
  # as the #85 guard in windowspowershell::external_module).
  $normalized_root_check = regsubst(regsubst(downcase($normalized_module_root), '/', '\\', 'G'), /\\+$/, '')
  $is_custom_root = $normalized_root_check != 'c:\\program files\\windowspowershell\\modules'
  # UNC roots (bare share roots included), extended-prefix ('\\?\') roots
  # and drive roots are never enforced: Test-Path in the 5.1 provider does
  # not understand the extended prefix (same reason the #96 guard skips
  # them), a bare share parent is not a checkable directory, and rewriting
  # the ACL of a whole drive would be destructive.
  $skip_module_root_acl = $normalized_module_root =~ /^[\/\\][\/\\]/ or $normalized_module_root =~ /^[A-Za-z]:[\/\\]?$/
  $manage_acl_effective = $manage_module_root_acl and $is_custom_root and !$skip_module_root_acl

  if $is_custom_root and !$manage_module_root_acl {
    warning("windowspowershell: custom module_root '${module_root}' (normalized '${normalized_module_root}') gets no ACL from this module: it inherits its parent's ACL, so a parent writable by non-administrators lets any writer plant code the agent then runs as SYSTEM (privilege escalation, issue #133). Restrict it to SYSTEM and Administrators Full control and verify with Get-Acl, or set manage_module_root_acl => true to enforce that from this module (UNC, extended-prefix and drive roots are never enforced: restrict those by hand).")
  }
  if $is_custom_root and $manage_module_root_acl and $skip_module_root_acl {
    warning("windowspowershell: manage_module_root_acl => true has no effect on module_root '${module_root}' (normalized '${normalized_module_root}'): UNC, extended-prefix ('\\\\?\\') and drive roots are never enforced by this module (issue #133). Restrict the directory to SYSTEM and Administrators Full control by hand and verify with Get-Acl.")
  }

  # Install-Module goes through .NET, whose default proxy is the *WinINET*
  # setting of the account running the agent. The agent runs as LocalSystem,
  # which never sees an interactive user's Internet Options, and it ignores the
  # machine-wide WinHTTP proxy entirely. So the proxy has to be passed to
  # Install-Module explicitly rather than inherited from the system.
  #
  # Proxy comes exclusively from the `$proxy` parameter: `undef` means a direct
  # install, a set value is passed through as-is. The
  # `Windowspowershell::Proxyurl` type validates it at compile time and keeps
  # it from ending the single-quoted PowerShell string it is embedded in.
  $proxy_url = $proxy

  # Validated on every node, like the defined types' parameters.
  if $proxy_credential =~ NotUndef and $proxy =~ Undef {
    fail("windowspowershell: 'proxy_credential' needs 'proxy': it only carries the credentials, the proxy URL comes from 'proxy'.")
  }
  if !$manage_profiles and $manage_pwsh_profile == true {
    fail("windowspowershell: 'manage_pwsh_profile' is true but 'manage_profiles' is false: no profile is managed, so the PowerShell 7 profile would be a silent no-op. Set 'manage_profiles' to true, or leave 'manage_pwsh_profile' unset/false.")
  }

  # The secret reaches the Exec through its environment, never through the
  # command text. The whole array is wrapped in Sensitive so that Puppet
  # redacts it from reports and logs.
  $proxy_use_credential = $proxy_credential =~ NotUndef
  $proxy_environment = $proxy_credential ? {
    undef   => undef,
    default => Sensitive($proxy_credential['password'].unwrap |$password| {
        [
          "WPS_PROXY_USER=${proxy_credential['username']}",
          "WPS_PROXY_PASSWORD=${password}",
        ]
    }),
  }

  # The `powershell7` fact is shipped by this module (lib/facter/powershell7.rb)
  # and reports whether pwsh.exe is on disk at its default location, the one
  # whose machine-wide profile this module manages. Installs elsewhere (ZIP,
  # Microsoft Store, 32-bit) are not detected, on purpose: they would not load
  # that profile.
  $pwsh7_installed = $facts.dig('powershell7', 'installed')
  $manage_pwsh = $manage_pwsh_profile ? {
    undef   => $pwsh7_installed,
    default => $manage_pwsh_profile,
  }

  # Every profile file windowspowershell::config manages, exposed here so that
  # windowspowershell::module and windowspowershell::external_module can target
  # the same set when asked to add an Import-Module line for a module.
  #
  # 32-bit Windows PowerShell reads its own profile from SysWOW64, not
  # System32. Without the SysWOW64 entry a module imported in the profile would
  # be missing from any 32-bit PowerShell session. SysWOW64\WindowsPowerShell\v1.0
  # exists on every 64-bit Windows, so the file can be written unconditionally.
  $profile_paths = $manage_profiles ? {
    false   => [],
    default => [
      'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1',
      'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1',
    ] + ($manage_pwsh ? { true => ['C:\Program Files\PowerShell\7\profile.ps1'], default => [] }),
  }

  if $supported {
    contain windowspowershell::install
    contain windowspowershell::config

    Class['windowspowershell::install'] -> Class['windowspowershell::config']
  }
}
