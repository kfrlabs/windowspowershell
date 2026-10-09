require 'spec_helper'

describe 'windowspowershell' do
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
        it { is_expected.not_to contain_file('C:\Program Files\PowerShell\7\profile.ps1') }
      end

      context 'with PowerShell 7 installed' do
        let(:facts) { os_facts.merge('powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' }) }

        it {
          is_expected.to contain_file('C:\Program Files\PowerShell\7\profile.ps1').
            with_content(%r{Set-PSReadLineOption -PredictionViewStyle ListView})
        }
      end

      context 'with PowerShell 7 installed but the profile opted out' do
        let(:facts) { os_facts.merge('powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' }) }
        let(:params) { { 'manage_pwsh_profile' => false } }

        it { is_expected.not_to contain_file('C:\Program Files\PowerShell\7\profile.ps1') }
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
          is_expected.to contain_file('C:\Program Files\PowerShell\7\profile.ps1').
            with_content(%r{Set-PSReadLineOption -PredictionViewStyle ListView})
        }
      end

      # Proxy configuration via the $proxy parameter (replaces http_proxy fact).
# If $proxy is undef, installations go out directly (no -Proxy flag).
# If $proxy is set, it is passed to Install-Module (supports auth URLs).
context 'proxy via $proxy parameter' do
  context 'without proxy (direct install)' do
    let(:params) { { 'proxy' => undef } }

    it { is_expected.to compile.with_all_deps }

    it 'goes out directly without -Proxy' do
      is_expected.to contain_exec('windowspowershell install nuget provider').
        with_command(%r{-Proxy }).
        that_matches(%r{-Proxy .*-Proxy} => %r{/})
    end
  end

  context 'with explicit proxy' do
    let(:params) { { 'proxy' => 'http://proxy.example.net:3128' } }

    it { is_expected.to compile.with_all_deps }

    it 'passes the proxy URL to the nuget bootstrap' do
      is_expected.to contain_exec('windowspowershell install nuget provider').
        with_command(%r{-Proxy 'http://proxy\.example\.net:3128'})
    end
  end

  context 'with authenticated proxy' do
    let(:params) { { 'proxy' => 'http://user:pass@proxy.example.net:3128' } }

    it { is_expected.to compile.with_all_deps }

    it 'passes the authenticated proxy URL' do
      is_expected.to contain_exec('windowspowershell install nuget provider').
        with_command(%r{-Proxy 'http://user:pass@proxy\.example\.net:3128'})
    end
  end
end

      context 'with manage_profiles => false' do
        let(:params) { { 'manage_profiles' => false } }

        it { is_expected.not_to contain_file('C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1') }
        it { is_expected.not_to contain_file('C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1') }
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
