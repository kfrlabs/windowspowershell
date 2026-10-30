# Bracketed repository-backend catalogue for the weekly schedule
# (issue #112, Gap 2; decided in issue #132).
#
# Applied by tools/Test-RepositoryBackend.ps1 -IncludeBrackets, which publishes
# a literal `Bracket[Beta] 1.0.0` fixture into the local `WpsLocal` file
# repository (proving the hand-packed nupkg serves and enumerates) and then
# asserts this catalogue FAILS TO COMPILE with the wildcard refusal: the
# repository backend cannot install wildcard names (PowerShellGet cannot
# address them, so installing would silently do nothing and reinstall on
# every run). Bracketed modules stay supported through the `source` backend
# and in-house modules, whose file operations use literal paths.
# Kept out of the per-PR gate: the brackets-free catalogue
# (`site_repository.pp`) converges per-PR while the refusal is proven on the
# weekly schedule.
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
