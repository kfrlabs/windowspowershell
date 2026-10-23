# Repository-backend counterpart of site.pp for issue #85.
#
# Applied twice by tools/Test-RepositoryBackend.ps1 (which registers the
# `WpsLocal` file repository for the account running the apply — SYSTEM in
# CI and on lab nodes — and publishes the fixture module into it): the first
# run converges, the second must report no changes. Uses the default
# `module_root` on purpose: `Install-Module -Scope AllUsers` always installs
# to `C:\Program Files\WindowsPowerShell\Modules` and ignores a custom root,
# so a custom root with `repository` fails compilation (see
# windowspowershell::external_module).
class { 'windowspowershell':
  module_root => 'C:\Program Files\WindowsPowerShell\Modules',
}

# Third-party module installed from the local repository (offline, no Gallery
# or NuGet network access beyond what bootstrapping an already-present
# provider needs). Pinned version keeps the catalogue deterministic.
windowspowershell::external_module { 'WpsRepoTest':
  ensure     => '1.0.0',
  repository => 'WpsLocal',
}
