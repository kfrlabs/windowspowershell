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
# @param manage_pwsh_profile
#   Whether to manage the PowerShell 7 profile. Left `undef`, it is managed
#   only on nodes where PowerShell 7 is installed. Set it in Hiera to opt a
#   whole agent environment in or out.
# @param proxy
#   Proxy passed to `Install-Module` when installing a third-party module from
#   a repository. Left `undef`, no proxy is used and installs go out directly.
#   Set it to an explicit proxy URL, including credentials when needed
#   (e.g. 'http://user:pass@proxy.example.net:3128').
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
# @example Deploy a third-party module
#   windowspowershell::external_module { 'PSWindowsUpdate':
#     ensure     => '2.2.1.5',
#     repository => 'PSGallery',
#   }
class windowspowershell (
  Windowspowershell::Rootpath $module_root = 'C:\Program Files\WindowsPowerShell\Modules',
  Boolean $manage_profiles = true,
  Optional[Boolean] $manage_pwsh_profile = undef,
  Optional[Stdlib::HTTPUrl] $proxy = undef,
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
  # install, a set value is passed through as-is. The `Stdlib::HTTPUrl` type
  # validates it at compile time.
  $proxy_url = $proxy

  # The `powershell7` fact is shipped by this module (lib/facter/powershell7.rb)
  # and reports whether pwsh.exe is actually on disk. That is more robust than
  # reading the `packages_version` inventory, which only sees the x64 MSI
  # install and misses ZIP/Store/winget/32-bit.
  $pwsh7_installed = $facts.dig('powershell7', 'installed')
  $manage_pwsh = $manage_pwsh_profile ? {
    undef   => $pwsh7_installed,
    default => $manage_pwsh_profile,
  }

  # Every profile file windowspowershell::config manages, exposed here so that
  # windowspowershell::module and windowspowershell::external_module can target
  # the same set when asked to add an Import-Module line for a module.
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
