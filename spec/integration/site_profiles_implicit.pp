# Profiles upgrade coverage, implicit phase (issue #129, R6).
#
# Applied twice by tools/Test-ProfilesUpgrade.ps1 after the managed phase.
# The class omits manage_profiles, exercising the implicit default (false),
# so no profile fragment is declared and the profile files stay as written
# by the managed phase. Both runs must report no changes (exit 0).
class { 'windowspowershell':
  module_root => 'C:\wps-int\Modules',
  # Pinned for determinism (review #129): no profile is managed here on any
  # host, whether or not pwsh exists.
  manage_pwsh_profile => false,
}

windowspowershell::module { 'WpsProfTest':
  import_in_profile => true,
}
