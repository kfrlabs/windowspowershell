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
#   Machine-wide PowerShell module directory, shared by every in-house module
#   this class lays out and by `windowspowershell::external_module`. The module manages this directory itself (via ensure_resource,
#   so it can be co-managed by another module), but its parent must already
#   exist.
# @param manage_profiles
#   Whether to manage the machine-wide PowerShell profiles. Each in-house
#   module with `import_in_profile => true` (the default) adds its own
#   `Import-Module` line to these profiles; `windowspowershell::external_module` does
#   the same for a third-party module when `import_in_profile => true` is
#   passed to it.
#   The profile files are owned by Puppet: on every run, anything in them that
#   does not come from a `concat::fragment` targeting them is removed. Other
#   Puppet code can add its own content by declaring a `concat::fragment` with
#   `target` set to a path in `$windowspowershell::profile_paths` and an
#   `order` between `01` and `49` (before the module imports) or `70` and `99`
#   (after them); `00` is the header, `50` the in-house imports and `60` the
#   external imports. Lines added by a GPO startup script or by hand are not
#   preserved. See "Co-managing the profiles" in the README.
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
  Boolean $manage_profiles = true,
  Optional[Boolean] $manage_pwsh_profile = undef,
  Optional[Windowspowershell::Proxyurl] $proxy = undef,
  Optional[Struct[{
        username => String[1],
        password => Sensitive[String[1]],
  }]] $proxy_credential = undef,
) {
  # Whether this node gets any resources at all. Read by
  # windowspowershell::script, windowspowershell::module and
  # windowspowershell::external_module, which must no-op on the same nodes this class
  # does, so that node classification never has to filter on the operating
  # system.
  $supported = $facts['os']['family'] == 'windows'

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
