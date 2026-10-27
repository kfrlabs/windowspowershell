# Scheduled Gallery end-to-end counterpart of site_repository.pp (issue #112,
# Gap 1). Applied by tools/Test-GalleryBackend.ps1 on the weekly schedule
# only: this is the one catalogue allowed to reach the real PowerShell
# Gallery, so per-PR jobs stay offline. Uses the default `module_root` on
# purpose: `Install-Module -Scope AllUsers` always installs to
# `C:\Program Files\WindowsPowerShell\Modules` and ignores a custom root
# (see windowspowershell::external_module).
class { 'windowspowershell':
  module_root => 'C:\Program Files\WindowsPowerShell\Modules',
}

# Pinned Gallery module: PSScriptAnalyzer 1.21.0 is Microsoft-owned, its
# version is already proven to exist by the proxy probe
# (tools/Test-ProxyBackend.ps1 defaults), and it is small enough for a weekly
# run while still exercising the real Install-Module path (including the
# publisher-trust prompt suppression) as SYSTEM.
windowspowershell::external_module { 'PSScriptAnalyzer':
  ensure     => '1.21.0',
  repository => 'PSGallery',
}
