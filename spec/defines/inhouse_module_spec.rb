require 'spec_helper'

describe 'windowspowershell::inhouse_module' do
  let(:title) { 'Acme' }

  modules = 'C:\Program Files\WindowsPowerShell\Modules'

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile.with_all_deps }

      it 'lays out the module under the default version, with neutral author/company' do
        is_expected.to contain_file("#{modules}\\Acme").with_ensure('directory')
        is_expected.to contain_file("#{modules}\\Acme\\1.0").with_ensure('directory')
        is_expected.to contain_file("#{modules}\\Acme\\1.0\\Functions").with_ensure('directory')
        is_expected.to contain_exec('windowspowershell update-manifest Acme').
          with_command(%r{-Author 'Unknown'}).
          with_command(%r{-CompanyName 'Unknown'})
      end

      it 'writes the root module and notifies the shared manifest exec' do
        is_expected.to contain_file("#{modules}\\Acme\\1.0\\Acme.psm1").
          with_ensure('file').
          that_notifies('Exec[windowspowershell update-manifest Acme]').
          that_notifies('Exec[windowspowershell unblock-files Acme]')
      end

      it 'declares the refresh-only manifest exec' do
        is_expected.to contain_exec('windowspowershell update-manifest Acme').with(
          'refreshonly' => true,
          'provider' => 'powershell'
        )
      end

      it 'declares the refresh-only unblock-files exec over the module tree' do
        is_expected.to contain_exec('windowspowershell unblock-files Acme').with(
          'refreshonly' => true,
          'provider' => 'powershell',
          'logoutput' => 'on_failure'
        )
        is_expected.to contain_exec('windowspowershell unblock-files Acme').
          with_command(%r{Get-ChildItem -Path 'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\\1\.0' -Recurse -File \| Unblock-File})
      end

      it 'declares a self-heal manifest exec gated on the manifest file' do
        is_expected.to contain_exec('windowspowershell create-manifest Acme').with(
          'creates' => 'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\\1.0\\Acme.psd1',
          'provider' => 'powershell'
        )
        is_expected.not_to contain_exec('windowspowershell create-manifest Acme').with_refreshonly(true)
      end

      it 'orders the self-heal exec before the refresh-only exec' do
        is_expected.to contain_exec('windowspowershell create-manifest Acme').
          that_comes_before('Exec[windowspowershell update-manifest Acme]')
      end

      it 'passes the same deterministic GUID to both manifest execs' do
        uuid = %r{-Guid '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'}
        create_cmd = catalogue.resource('Exec', 'windowspowershell create-manifest Acme')[:command]
        update_cmd = catalogue.resource('Exec', 'windowspowershell update-manifest Acme')[:command]
        expect(create_cmd).to match(uuid)
        expect(update_cmd).to match(uuid)
        expect(create_cmd[uuid, 1]).to eq(update_cmd[uuid, 1])
      end

      it 'scans only the Functions directory when building the manifest' do
        is_expected.to contain_exec('windowspowershell update-manifest Acme').
          with_command(%r{\$functionsPath\s*=\s*'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\\1\.0\\Functions'}).
          with_command(%r{Get-ChildItem -Path \$functionsPath})
      end

      it 'declares the root module only as -RootModule, not from the scan' do
        is_expected.to contain_exec('windowspowershell update-manifest Acme').
          with_command(%r{-RootModule "\$\{moduleName\}\.psm1"})
      end

      it 'imports the module from the Windows PowerShell profile by default' do
        is_expected.to contain_file('C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1').
          with_content(%r{Import-Module 'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\\1\.0\\Acme\.psd1'})
        is_expected.to contain_file('C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1').
          with_content(%r{Import-Module 'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\\1\.0\\Acme\.psd1'})
      end

      context 'with import_in_profile => false' do
        let(:params) { { 'import_in_profile' => false } }

        it 'adds no Import-Module line to the profiles' do
          is_expected.to contain_file('C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1').without_content(%r{Acme})
        end
      end

      it 'logs the manifest Exec output on failure' do
        is_expected.to contain_exec('windowspowershell create-manifest Acme').with_logoutput('on_failure')
        is_expected.to contain_exec('windowspowershell update-manifest Acme').with_logoutput('on_failure')
      end

      context 'with a non-default version, companyname and author' do
        let(:params) { { 'version' => '2.3', 'companyname' => 'Acme Corp', 'author' => 'Platform Team' } }

        it { is_expected.to compile.with_all_deps }

        it 'lays the module out under the custom version' do
          is_expected.to contain_file("#{modules}\\Acme\\2.3").with_ensure('directory')
        end

        it 'writes the custom author and company into the manifest' do
          is_expected.to contain_exec('windowspowershell update-manifest Acme').
            with_command(%r{-Author 'Platform Team'}).
            with_command(%r{-CompanyName 'Acme Corp'})
        end
      end

      context 'with a title holding an apostrophe' do
        let(:title) { "Evil'; calc.exe #" }

        it { is_expected.to compile.and_raise_error(%r{title expects a match}) }
      end

      context 'with a title that is the parent directory' do
        let(:title) { '..' }

        it { is_expected.to compile.and_raise_error(%r{title expects a match}) }
      end

      context 'with a version that is not a version' do
        let(:params) { { 'version' => "1.0'; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'version'}) }
      end

      context 'with an author holding an apostrophe' do
        let(:params) { { 'author' => "Evil'; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'author'}) }
      end

      context 'with a companyname holding an apostrophe' do
        let(:params) { { 'companyname' => "Evil'; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'companyname'}) }
      end

      # A company name is free text, not a path component: spaces and dots
      # have to keep working.
      context 'with a company name holding spaces and a dot' do
        let(:params) { { 'companyname' => 'Acme S.A.S.' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_exec('windowspowershell update-manifest Acme').with_command(%r{-CompanyName 'Acme S\.A\.S\.'}) }
      end

      context 'with two modules declared, each one self-contained' do
        let(:pre_condition) { "windowspowershell::inhouse_module { 'OtherModule': }" }

        it { is_expected.to compile.with_all_deps }

        it 'declares independent trees and Execs for each' do
          is_expected.to contain_file("#{modules}\\Acme\\1.0")
          is_expected.to contain_file("#{modules}\\OtherModule\\1.0")
          is_expected.to contain_exec('windowspowershell update-manifest Acme')
          is_expected.to contain_exec('windowspowershell update-manifest OtherModule')
        end
      end

      context 'with a source: dynamic, directory-wide deployment' do
        let(:params) { { 'source' => 'puppet:///modules/profile/acme-scripts' } }

        it { is_expected.to compile.with_all_deps }

        it 'recurses and purges Functions from the given source' do
          is_expected.to contain_file("#{modules}\\Acme\\1.0\\Functions").with(
            'ensure' => 'directory',
            'recurse' => true,
            'purge' => true,
            'source' => 'puppet:///modules/profile/acme-scripts'
          ).that_notifies('Exec[windowspowershell update-manifest Acme]').
            that_notifies('Exec[windowspowershell unblock-files Acme]')
        end
      end

      context 'without a source: no bulk deployment' do
        it 'declares a plain directory, with no recurse/purge/source' do
          is_expected.to contain_file("#{modules}\\Acme\\1.0\\Functions").with(
            'ensure' => 'directory',
            'recurse' => false,
            'purge' => false
          )
        end
      end
    end
  end

  context 'on a non-Windows node' do
    let(:facts) { { 'os' => { 'family' => 'RedHat', 'name' => 'RedHat' } } }

    it { is_expected.to compile.with_all_deps }

    it 'declares nothing at all' do
      expect(catalogue.resources.select { |r| %w[File Exec Concat::Fragment].include?(r.type) }).to be_empty
    end
  end
end
