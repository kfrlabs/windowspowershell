require 'spec_helper'

describe 'windowspowershell' do
  # Mixed in-house + external imports (issue #12): both fragments land
  # on the same concat target under distinct titles however they are
  # declared, and the header (00) sorts before the in-house (50) and
  # external (60) imports.
  shared_examples 'mixed in-house and external profile imports' do
    it { is_expected.to compile.with_all_deps }

    it 'keeps both Import-Module fragments under distinct titles' do
      profile = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
      is_expected.to contain_concat_fragment("windowspowershell import Acme in #{profile}").
        with_target(profile).
        with_content(%r{Acme\.psd1})
      is_expected.to contain_concat_fragment("windowspowershell import external ExampleModule in #{profile}").
        with_target(profile).
        with_content(%r{Import-Module 'ExampleModule'})
    end

    it 'orders the header before the in-house import before the external import' do
      profile = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
      orders = catalogue.resources.select { |r| r.type == 'Concat::Fragment' && r[:target] == profile }.
        to_h { |r| [r.title, r[:order]] }
      expect(orders["windowspowershell header #{profile}"]).to eq('00')
      expect(orders["windowspowershell import Acme in #{profile}"]).to eq('50')
      expect(orders["windowspowershell import external ExampleModule in #{profile}"]).to eq('60')
    end
  end

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile.with_all_deps }

      # No mandatory parameter any more: the in-house module identity moved
      # to windowspowershell::module, so `include windowspowershell`
      # alone must compile and lay out nothing but the shared module root.
      it 'declares only the shared module root, nothing module-specific' do
        is_expected.to contain_file('C:\Program Files\WindowsPowerShell\Modules').with_ensure('directory')
        is_expected.not_to contain_exec('windowspowershell update-manifest')
        is_expected.not_to contain_exec('windowspowershell create-manifest')
        is_expected.not_to contain_exec('windowspowershell unblock-files')
      end

      it 'declares a concat target and header fragment per Windows PowerShell profile' do
        [
          'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1',
          'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1',
        ].each do |profile|
          is_expected.to contain_concat(profile).with_ensure('present')
          is_expected.to contain_concat_fragment("windowspowershell header #{profile}").
            with_target(profile).
            with_order('00').
            with_content(%r{Managed by Puppet \(windowspowershell\)})
        end
      end

      context 'with a module_root breaking out of the quoted path' do
        let(:params) { { 'module_root' => "C:\\x'; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'module_root'}) }
      end

      context 'with a module_root holding spaces' do
        let(:params) { { 'module_root' => 'C:\\Program Files\\Custom\\Modules' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file('C:\\Program Files\\Custom\\Modules').with_ensure('directory') }
      end

      context 'with a UNC module_root' do
        let(:params) { { 'module_root' => '\\\\serveur\\partage\\Modules' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file('\\\\serveur\\partage\\Modules').with_ensure('directory') }
      end

      context 'without PowerShell 7' do
        it { is_expected.not_to contain_concat('C:\Program Files\PowerShell\7\profile.ps1') }
      end

      context 'with PowerShell 7 installed' do
        let(:facts) { os_facts.merge('powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' }) }

        it {
          is_expected.to contain_concat('C:\Program Files\PowerShell\7\profile.ps1').with_ensure('present')
          is_expected.to contain_concat_fragment('windowspowershell header C:\Program Files\PowerShell\7\profile.ps1').
            with_target('C:\Program Files\PowerShell\7\profile.ps1').
            with_order('00').
            with_content(%r{Set-PSReadLineOption -PredictionViewStyle ListView})
        }
      end

      context 'with PowerShell 7 installed but the profile opted out' do
        let(:facts) { os_facts.merge('powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' }) }
        let(:params) { { 'manage_pwsh_profile' => false } }

        it { is_expected.not_to contain_concat('C:\Program Files\PowerShell\7\profile.ps1') }
      end

      # Forcing the pwsh profile on a node where PowerShell 7 is absent would
      # write into a directory that does not exist; the class fails early with a
      # clear message instead of letting the run blow up opaquely later.
      context 'with the pwsh profile forced on but PowerShell 7 absent' do
        let(:params) { { 'manage_pwsh_profile' => true } }

        it { is_expected.to compile.and_raise_error(%r{manage_pwsh_profile is true but PowerShell 7 was not detected}) }
      end

      # Forced on and pwsh present: the profile is managed as expected.
      context 'with the pwsh profile forced on and PowerShell 7 present' do
        let(:facts) { os_facts.merge('powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' }) }
        let(:params) { { 'manage_pwsh_profile' => true } }

        it {
          is_expected.to contain_concat('C:\Program Files\PowerShell\7\profile.ps1').with_ensure('present')
          is_expected.to contain_concat_fragment('windowspowershell header C:\Program Files\PowerShell\7\profile.ps1').
            with_target('C:\Program Files\PowerShell\7\profile.ps1').
            with_order('00').
            with_content(%r{Set-PSReadLineOption -PredictionViewStyle ListView})
        }
      end

      # $proxy_url is built in init.pp but only surfaces through an Exec, so a
      # probe module (declared here, not by the class) is what makes the
      # bootstrap nuget Exec carry the -Proxy the class computed.
      context 'proxy via the $proxy parameter' do
        let(:pre_condition) { "windowspowershell::external_module { 'ProxyProbe': repository => 'PSGallery' }" }

        context 'without proxy' do
          it { is_expected.to compile.with_all_deps }

          it 'goes out directly with no -Proxy' do
            cmd = catalogue.resource('Exec', 'windowspowershell install nuget provider')[:command]
            expect(cmd).not_to match(%r{-Proxy})
          end
        end

        context 'with an explicit proxy' do
          let(:params) { { 'proxy' => 'http://proxy.example.net:3128' } }

          it { is_expected.to compile.with_all_deps }

          it 'passes the proxy URL to the nuget bootstrap' do
            is_expected.to contain_exec('windowspowershell install nuget provider').
              with_command(%r{-Proxy 'http://proxy\.example\.net:3128'})
          end
        end

        context 'with an authenticated proxy' do
          let(:params) { { 'proxy' => 'http://user:pass@proxy.example.net:3128' } }

          it { is_expected.to compile.with_all_deps }

          it 'passes the authenticated proxy URL to the nuget bootstrap' do
            is_expected.to contain_exec('windowspowershell install nuget provider').
              with_command(%r{-Proxy 'http://user:pass@proxy\.example\.net:3128'})
          end
        end

        context 'with an invalid proxy' do
          let(:params) { { 'proxy' => 'not a url' } }

          it { is_expected.to compile.and_raise_error(%r{parameter 'proxy'}) }
        end

        # No site-provided fact feeds the proxy any more: a stray http_proxy
        # fact must not leak a -Proxy onto the command.
        context 'with a stray http_proxy fact and no proxy parameter' do
          let(:facts) { os_facts.merge('http_proxy' => { 'host' => 'proxy.example.net', 'port' => 8080 }) }

          it { is_expected.to compile.with_all_deps }

          it 'ignores the fact and goes out directly' do
            cmd = catalogue.resource('Exec', 'windowspowershell install nuget provider')[:command]
            expect(cmd).not_to match(%r{-Proxy})
          end
        end
      end

      context 'with manage_profiles => false' do
        let(:params) { { 'manage_profiles' => false } }

        it { is_expected.not_to contain_concat('C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1') }
        it { is_expected.not_to contain_concat('C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1') }
        it { is_expected.not_to contain_concat('C:\Program Files\PowerShell\7\profile.ps1') }
        it { is_expected.not_to contain_concat_fragment('windowspowershell header C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1') }
        it { is_expected.not_to contain_concat_fragment('windowspowershell header C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1') }
        it { is_expected.not_to contain_concat_fragment('windowspowershell header C:\Program Files\PowerShell\7\profile.ps1') }
      end

      context 'with an in-house and an external module importing into the profile' do
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::external_module { 'ExampleModule':
              ensure            => '2.1.0',
              repository        => 'PSGallery',
              import_in_profile => true,
            }
            windowspowershell::module { 'Acme': }
          PUPPET
        end

        it_behaves_like 'mixed in-house and external profile imports'
      end

      # Same pair declared in the reverse order (module first, external
      # second): declaration order must not change the fragment set.
      context 'with the same in-house and external modules declared in reverse order' do
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::module { 'Acme': }
            windowspowershell::external_module { 'ExampleModule':
              ensure            => '2.1.0',
              repository        => 'PSGallery',
              import_in_profile => true,
            }
          PUPPET
        end

        it_behaves_like 'mixed in-house and external profile imports'
      end

      context 'with PowerShell 7 installed and mixed imports into the pwsh profile' do
        let(:facts) { os_facts.merge('powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' }) }
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::module { 'Acme': }
            windowspowershell::external_module { 'ExampleModule':
              ensure            => '2.1.0',
              repository        => 'PSGallery',
              import_in_profile => true,
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'keeps both Import-Module fragments on the pwsh profile' do
          profile = 'C:\Program Files\PowerShell\7\profile.ps1'
          is_expected.to contain_concat_fragment("windowspowershell import Acme in #{profile}").
            with_target(profile).
            with_order('50').
            with_content(%r{Acme\.psd1})
          is_expected.to contain_concat_fragment("windowspowershell import external ExampleModule in #{profile}").
            with_target(profile).
            with_order('60').
            with_content(%r{Import-Module 'ExampleModule'})
        end

        it 'orders the pwsh header before the in-house import before the external import' do
          profile = 'C:\Program Files\PowerShell\7\profile.ps1'
          orders = catalogue.resources.select { |r| r.type == 'Concat::Fragment' && r[:target] == profile }.
            to_h { |r| [r.title, r[:order]] }
          expect(orders["windowspowershell header #{profile}"]).to eq('00')
          expect(orders["windowspowershell import Acme in #{profile}"]).to eq('50')
          expect(orders["windowspowershell import external ExampleModule in #{profile}"]).to eq('60')
        end
      end
    end
  end

  context 'on a non-Windows node' do
    let(:facts) { { 'os' => { 'family' => 'RedHat', 'name' => 'RedHat' } } }

    it { is_expected.to compile.with_all_deps }

    it 'is a no-op' do
      is_expected.not_to contain_class('windowspowershell::install')
      is_expected.not_to contain_class('windowspowershell::config')
      expect(catalogue.resources.reject { |r| %w[Class Stage Node].include?(r.type) }).to be_empty
    end
  end
end
