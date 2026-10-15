# @summary Lays out the machine-wide PowerShell profiles that
#   in-house and external modules add their Import-Module lines to.
#
# This class owns no module identity: it only declares the `concat` targets.
# Each `windowspowershell::module` (when `import_in_profile => true`,
# the default) and each `windowspowershell::external_module` (when
# `import_in_profile => true` is passed) attaches its own `concat::fragment`
# to the paths listed in `$windowspowershell::profile_paths`.
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
        fail('windowspowershell: manage_pwsh_profile is true but PowerShell 7 was not detected (no pwsh.exe). Install PowerShell 7, or leave manage_pwsh_profile unset to manage the profile only where PowerShell 7 is present.')
      }
    }

    # 32-bit Windows PowerShell reads its own profile from SysWOW64, not
    # System32. Without this a module imported in the profile would be
    # missing from any 32-bit PowerShell session. SysWOW64\WindowsPowerShell\v1.0
    # exists on every 64-bit Windows, so the file can be written
    # unconditionally.
    $pwsh_profile = 'C:\Program Files\PowerShell\7\profile.ps1'

    $windowspowershell::profile_paths.each |$profile_path| {
      concat { $profile_path:
        ensure => present,
      }

      # The PowerShell 7 profile ships a richer header (predictive
      # IntelliSense); Windows PowerShell profiles get a plain
      # managed-by-Puppet header.
      concat::fragment { "windowspowershell header ${profile_path}":
        target  => $profile_path,
        order   => '00',
        content => $profile_path ? {
          $pwsh_profile => epp('windowspowershell/pwsh_profile.ps1.epp'),
          default       => "# Managed by Puppet (windowspowershell).\n",
        },
      }
    }
  }
}
