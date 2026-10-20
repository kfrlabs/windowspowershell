# @summary Lays out the machine-wide PowerShell profiles that
#   in-house and external modules add their Import-Module lines to.
#
# This class owns no module identity: it only declares the `concat` targets.
# Each `windowspowershell::module` (when `import_in_profile => true`,
# the default) and each `windowspowershell::external_module` (when
# `import_in_profile => true` is passed) attaches its own `concat::fragment`
# to the paths listed in `$windowspowershell::profile_paths`.
#
# The targets are standard `concat` resources, so any other Puppet code can add
# its own `concat::fragment` to them too. The ordering convention is: `00` the
# header (declared here), `01`-`49` free, `50` in-house module imports, `60`
# external module imports, `70`-`99` free. Content that does not come from a
# fragment is removed on the next run.
#
# @api private
class windowspowershell::config {
  assert_private()

  if $windowspowershell::manage_profiles {
    # Forcing the profile on a node without PowerShell 7 would write
    # profile.ps1 into a directory that does not exist, failing the run with
    # an opaque error. Fail early with a clear, actionable message instead.
    if $windowspowershell::manage_pwsh {
      unless $windowspowershell::pwsh7_installed {
        fail('windowspowershell: manage_pwsh_profile is true but PowerShell 7 was not detected at its default location (no pwsh.exe under C:\Program Files\PowerShell\7). Only that install is supported, since its machine-wide profile is the one this module manages: a ZIP, Microsoft Store or 32-bit install elsewhere is not detected. Install PowerShell 7 at the default location (MSI), or leave manage_pwsh_profile unset to manage the profile only where it is present.')
      }
    }

    $pwsh_profile = 'C:\Program Files\PowerShell\7\profile.ps1'

    $windowspowershell::profile_paths.each |$profile_path| {
      concat { $profile_path:
        ensure => present,
      }

      # The PowerShell 7 profile ships a richer header (predictive
      # IntelliSense); Windows PowerShell profiles get a plain
      # managed-by-Puppet header.
      $header_content = $profile_path ? {
        $pwsh_profile => epp('windowspowershell/pwsh_profile.ps1.epp'),
        default       => "# Managed by Puppet (windowspowershell).\n",
      }
      concat::fragment { "windowspowershell header ${profile_path}":
        target  => $profile_path,
        order   => '00',
        content => $header_content,
      }
    }
  }
}
