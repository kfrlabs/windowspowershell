# Bracketed repository-backend catalogue for the weekly schedule
# (issue #112, Gap 2).
#
# Applied by tools/Test-RepositoryBackend.ps1 -IncludeBrackets, which publishes
# both fixture modules into the local `WpsLocal` file repository: the proven
# `WpsRepoTest 1.0.0` plus the literal `Bracket[Beta] 1.0.0` that proves the
# wildcard-escaped install path converges for real (the Gallery has no
# bracketed names, so only a file repo can cover it). The install check only
# requires the .psd1 to exist for wildcard names (see
# templates/check_psmodule.ps1.epp), which still repairs an empty folder.
# Kept out of the per-PR gate until the first Windows green run: the bracket
# publish path (Publish-Module with bracketed filenames) has zero Windows
# evidence yet.
class { 'windowspowershell':
  module_root => 'C:\Program Files\WindowsPowerShell\Modules',
}

windowspowershell::external_module { 'WpsRepoTest':
  ensure     => '1.0.0',
  repository => 'WpsLocal',
}

windowspowershell::external_module { 'Bracket[Beta]':
  ensure     => '1.0.0',
  repository => 'WpsLocal',
}
