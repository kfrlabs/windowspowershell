# @summary Bootstraps PowerShellGet so modules can be installed from a
#   repository.
#
# Included on demand by `windowspowershell::module`, and therefore absent from
# nodes that only deploy scripts or file-sourced modules.
#
# Only the NuGet package provider is managed here. The repository's
# InstallationPolicy is deliberately left alone: `Install-Module -Force`
# suppresses the untrusted-repository prompt without mutating machine-wide
# PowerShellGet configuration that other tooling may rely on.
#
# @api private
class windowspowershell::psget {
  assert_private()

  # PowerShellGet needs NuGet to talk to a NuGet-backed repository, and
  # Windows Server 2016 ships without it. Bootstrapping it is itself an
  # outbound call, hence the TLS 1.2 opt-in and the proxy.
  exec { 'windowspowershell install nuget provider':
    command   => epp('windowspowershell/install_nuget.ps1.epp', {
        'proxy' => $windowspowershell::proxy_url,
    }),
    unless    => epp('windowspowershell/check_nuget.ps1.epp'),
    provider  => powershell,
    timeout   => 300,
    logoutput => on_failure,
  }
}
