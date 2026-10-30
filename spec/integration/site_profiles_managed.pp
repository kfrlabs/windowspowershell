# Profiles upgrade coverage, managed phase (issue #129, R6).
#
# Applied twice by tools/Test-ProfilesUpgrade.ps1: the first run converges
# (exit 2), the second must report no changes (exit 0). The class manages
# the profiles, so the WpsProfTest Import-Module line lands in each managed
# profile. The module declares no scripts: an empty Functions/ is a
# supported no-op (see templates/update_manifest.ps1.epp).
class { 'windowspowershell':
  module_root     => 'C:\wps-int\Modules',
  manage_profiles => true,
  # Pinned for determinism (review #129): only the two 5.1 profiles are
  # snapshotted and asserted, on every host, whether or not pwsh exists.
  manage_pwsh_profile => false,
}

windowspowershell::module { 'WpsProfTest':
  import_in_profile => true,
}
