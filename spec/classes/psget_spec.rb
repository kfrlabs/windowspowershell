require 'spec_helper'

# windowspowershell::psget is @api private: its only legitimate caller is
# windowspowershell::external_module when installing from a repository. It is therefore
# tested here, through that caller -- covering both the privacy guarantee and
# the NuGet-provider bootstrap Exec the class declares (its guard, timeout,
# log policy and proxy propagation), which module_spec only touches
# incidentally.
describe 'windowspowershell::external_module', type: :define do
  let(:title) { 'ExampleModule' }

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      # assert_private(): included straight from a site manifest -- alongside a
      # module resource that does not touch psget -- the compile must abort.
      context 'included directly from outside the module' do
        let(:params) { { 'ensure' => 'absent' } }
        let(:pre_condition) { 'include windowspowershell::psget' }

        it { is_expected.to compile.and_raise_error(%r{private}) }
      end

      # Installing from a repository is the one path that pulls psget in.
      context 'pulled in by a repository install' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }

        it { is_expected.to compile.with_all_deps }

        it 'pulls in the private psget class' do
          is_expected.to contain_class('windowspowershell::psget')
        end

        # The guard keeps the bootstrap idempotent: NuGet is installed only when
        # Get-PackageProvider does not already report it.
        it 'declares the bootstrap Exec with its guard, timeout and log policy' do
          is_expected.to contain_exec('windowspowershell install nuget provider').with(
            'provider' => 'powershell',
            'timeout' => 300,
            'logoutput' => 'on_failure'
          ).with_unless(%r{Get-PackageProvider -Name NuGet}).
            with_command(%r{Install-PackageProvider -Name NuGet})
        end

        # Bootstrapping NuGet is itself an outbound call, so the script opts into
        # TLS 1.2 before reaching out.
        it 'opts into TLS 1.2 for the outbound call' do
          is_expected.to contain_exec('windowspowershell install nuget provider').
            with_command(%r{Tls12})
        end

        # No proxy fact and no explicit proxy: the bootstrap goes out directly,
        # with no -Proxy on the command. rspec-puppet's without_command only
        # compares literals, so the negative assertion reads the catalogue.
        context 'with no proxy configured' do
          it 'sends no -Proxy to the bootstrap' do
            cmd = catalogue.resource('Exec', 'windowspowershell install nuget provider')[:command]
            expect(cmd).not_to match(%r{-Proxy})
          end
        end

        # The proxy the init.pp class assembles from the http_proxy fact must
        # reach the bootstrap command.
        context 'with an http_proxy fact carrying host and port' do
          let(:facts) { os_facts.merge('http_proxy' => { 'host' => 'proxy.example.net', 'port' => 8080 }) }

          it 'propagates the assembled proxy URL to the bootstrap' do
            is_expected.to contain_exec('windowspowershell install nuget provider').
              with_command(%r{-Proxy 'http://proxy\.example\.net:8080'})
          end
        end
      end
    end
  end
end
