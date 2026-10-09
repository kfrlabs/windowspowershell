# @summary Lays out the machine-wide PowerShell profile skeletons that
#   in-house and third-party modules add their Import-Module lines to.
#
# This class owns no module identity: it only declares the `concat` targets.
# Each `windowspowershell::inhouse_module` (when `import_in_profile => true`,
# the default) and each `windowspowershell::module` (when
# `import_in_profile => true` is passed) attaches its own `concat::fragment`
# to the paths listed in `$windowspowershell::profile_paths`.
#
# @api private
class windowspowershell::config {
  assert_private()

  if $windowspowershell::manage_profiles {
    # Plain file skeletons: each in-house or third-party module that opts
    # into profile import amends these with a collector (see
    # windowspowershell::inhouse_module), so the Import-Module lines live on
    # the File resources themselves, where rspec-puppet and `puppet resource`
    # can see them.
    file { [
        'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1',
        'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1',
      ]:
        ensure  => file,
        content => "# Managed by Puppet (windowspowershell).\n",
    }

    # 32-bit Windows PowerShell reads its own profile from SysWOW64, not
    # System32. Without this a module imported in the profile would be
    # missing from any 32-bit PowerShell session. SysWOW64\WindowsPowerShell\v1.0
    # exists on every 64-bit Windows, so the file can be written
    # unconditionally.

    if $windowspowershell::manage_pwsh {
      # Forcing the profile on a node without PowerShell 7 would write
      # profile.ps1 into a directory that does not exist, failing the run with
      # an opaque error. Fail early with a clear, actionable message instead.
      unless $windowspowershell::pwsh7_installed {
        fail('windowspowershell: manage_pwsh_profile is true but PowerShell 7 was not detected (no pwsh.exe). Install PowerShell 7, or leave manage_pwsh_profile unset to manage the profile only where PowerShell 7 is present.')
      }

      file { 'C:\Program Files\PowerShell\7\profile.ps1':
        ensure  => file,
        content => epp('windowspowershell/pwsh_profile.ps1.epp'),
      }
    }
  }
}
