require 'spec_helper'

describe 'windowspowershell::external_module' do
  let(:title) { 'ExampleModule' }
  let(:pre_condition) { '' }

  modules = 'C:\Program Files\WindowsPowerShell\Modules'

  # rspec-puppet's without_<param> matchers only compare literals, so negative
  # assertions on command bodies read the catalogue directly.
  def command_of(title)
    catalogue.resource('Exec', title)[:command]
  end

  def unless_of(title)
    catalogue.resource('Exec', title)[:unless]
  end

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'from a repository, with a pinned version' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }

        it { is_expected.to compile.with_all_deps }

        it 'bootstraps NuGet before installing' do
          is_expected.to contain_class('windowspowershell::psget')
          is_expected.to contain_exec('windowspowershell install nuget provider').
            with_unless(%r{Get-PackageProvider -Name NuGet})
          is_expected.to contain_exec('windowspowershell install ExampleModule').
            that_requires('Exec[windowspowershell install nuget provider]')
        end

        it 'pins the version and forces past the trust prompt' do
          is_expected.to contain_exec('windowspowershell install ExampleModule').
            with_command(%r{Install-Module -Name 'ExampleModule'}).
            with_command(%r{-RequiredVersion '2\.1\.0'}).
            with_command(%r{-Scope AllUsers}).
            with_command(%r{-Force}).
            with_provider('powershell')
        end

        it 'opts in to TLS 1.2 for the outbound call' do
          is_expected.to contain_exec('windowspowershell install ExampleModule').
            with_command(%r{SecurityProtocolType\]::Tls12})
        end

        it 'checks the module directory, not the whole PSModulePath, to stay idempotent' do
          is_expected.to contain_exec('windowspowershell install ExampleModule').
            with_unless(%r{\$moduleDir = '#{Regexp.escape("#{modules}\\ExampleModule")}'}).
            with_unless(%r{Get-ChildItem -LiteralPath \$moduleDir -Directory}).
            with_unless(%r{\$_\.Name -eq '2\.1\.0'})
          expect(unless_of('windowspowershell install ExampleModule')).not_to match(%r{Get-Module -ListAvailable})
        end

        it 'purges the other versions after installing' do
          is_expected.to contain_exec('windowspowershell purge other versions of ExampleModule').
            with_command(%r{Where-Object \{ \$_\.Name -ne '2\.1\.0' \}}).
            that_requires('Exec[windowspowershell install ExampleModule]')
        end

        it 'declares no file resource for a repository-backed module' do
          is_expected.not_to contain_file("#{modules}\\ExampleModule")
        end
      end

      context 'from a repository, without a proxy' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:params_proxy_undef) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'proxy' => undef } }

        it 'passes no -Proxy at all (no proxy parameter)' do
          expect(command_of('windowspowershell install ExampleModule')).not_to match(%r{-Proxy})
          expect(command_of('windowspowershell install nuget provider')).not_to match(%r{-Proxy})
        end
      end

      context 'from a repository, with explicit proxy' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:params_proxy) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'proxy' => 'http://172.18.69.200:8080' } }

        it 'passes the proxy to Install-Module and to the NuGet bootstrap' do
          is_expected.to contain_exec('windowspowershell install ExampleModule').
            with_command(%r{-Proxy 'http://172\.18\.69\.200:8080'})
          is_expected.to contain_exec('windowspowershell install nuget provider').
            with_command(%r{-Proxy 'http://172\.18\.69\.200:8080'})
        end
      end

      context 'from a repository, with authenticated proxy' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:params_proxy_auth) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'proxy' => 'http://user:pass@172.18.69.200:8080' } }

        it 'passes the authenticated proxy to Install-Module and to the NuGet bootstrap' do
          is_expected.to contain_exec('windowspowershell install ExampleModule').
            with_command(%r{-Proxy 'http://user:pass@172\.18\.69\.200:8080'})
          is_expected.to contain_exec('windowspowershell install nuget provider').
            with_command(%r{-Proxy 'http://user:pass@172\.18\.69\.200:8080'})
        end
      end

      context 'from a repository, with the proxy overridden on the class' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:pre_condition) { "class { 'windowspowershell': proxy => 'http://other.proxy:3128' }" }

        it { is_expected.to contain_exec('windowspowershell install ExampleModule').with_command(%r{-Proxy 'http://other\.proxy:3128'}) }
      end

      context 'from a repository, with ensure => present' do
        let(:params) { { 'ensure' => 'present', 'repository' => 'PSGallery' } }

        it { is_expected.to compile.with_all_deps }

        it 'does not pin a version' do
          expect(command_of('windowspowershell install ExampleModule')).not_to match(%r{-RequiredVersion})
        end

        it 'accepts any installed version' do
          expect(unless_of('windowspowershell install ExampleModule')).not_to match(%r{-eq})
          expect(unless_of('windowspowershell install ExampleModule')).not_to match(%r{Get-Module -ListAvailable})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$moduleDir = '#{Regexp.escape("#{modules}\\ExampleModule")}'})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Get-ChildItem -LiteralPath \$moduleDir -Directory})
        end

        it 'purges nothing, since no version is targeted' do
          is_expected.not_to contain_exec('windowspowershell purge other versions of ExampleModule')
        end
      end

      context 'with purge_versions => false' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'purge_versions' => false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_exec('windowspowershell purge other versions of ExampleModule') }
      end

      context 'from a Puppet file source' do
        let(:params) do
          { 'ensure' => '2.2.1.5', 'source' => 'puppet:///modules/windowsupdate/PSWindowsUpdate/2.2.1.5/' }
        end

        it { is_expected.to compile.with_all_deps }

        it 'copies the version directory' do
          is_expected.to contain_file("#{modules}\\ExampleModule").with_ensure('directory')
          is_expected.to contain_file("#{modules}\\ExampleModule\\2.2.1.5").with(
            'ensure' => 'directory',
            'recurse' => true,
            'source' => 'puppet:///modules/windowsupdate/PSWindowsUpdate/2.2.1.5/'
          )
        end

        it 'does not bootstrap PowerShellGet' do
          is_expected.not_to contain_class('windowspowershell::psget')
        end

        it 'still purges the other versions' do
          is_expected.to contain_exec('windowspowershell purge other versions of ExampleModule').
            that_requires("File[#{modules}\\ExampleModule\\2.2.1.5]")
        end
      end

      context 'with the default file source' do
        let(:params) { { 'ensure' => '2.1.0' } }

        it { is_expected.to contain_file("#{modules}\\ExampleModule\\2.1.0").with_source('puppet:///modules/windowspowershell/modules/ExampleModule/2.1.0/') }
      end

      context 'with ensure => absent' do
        let(:params) { { 'ensure' => 'absent' } }

        it { is_expected.to compile.with_all_deps }

        it 'unregisters from PowerShellGet and removes the whole tree' do
          is_expected.to contain_exec('windowspowershell uninstall ExampleModule').
            with_command(%r{Uninstall-Module -Name 'ExampleModule' -AllVersions -Force}).
            with_command(%r{\$moduleDir = '#{Regexp.escape("#{modules}\\ExampleModule")}'}).
            with_command(%r{Remove-Item -LiteralPath \$moduleDir -Recurse -Force}).
            with_provider('powershell')
        end

        it 'stays idempotent on directory absence and the PowerShellGet record' do
          is_expected.to contain_exec('windowspowershell uninstall ExampleModule').
            with_unless(%r{\$moduleDir = '#{Regexp.escape("#{modules}\\ExampleModule")}'}).
            with_unless(%r{Get-InstalledModule -Name 'ExampleModule' -AllVersions})
        end

        it 'declares no file resource for the module' do
          is_expected.not_to contain_file("#{modules}\\ExampleModule")
        end

        it 'installs and purges nothing' do
          is_expected.not_to contain_exec('windowspowershell install ExampleModule')
          is_expected.not_to contain_exec('windowspowershell purge other versions of ExampleModule')
        end
      end

      context 'with ensure => absent and a modulename that breaks out of the quoted string' do
        let(:params) { { 'ensure' => 'absent', 'modulename' => "Evil'; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'modulename'}) }
      end

      context 'with ensure => absent and a modulename that is the parent directory' do
        let(:params) { { 'ensure' => 'absent', 'modulename' => '..' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'modulename'}) }
      end

      context 'with both repository and source' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'source' => 'puppet:///modules/x/y/' } }

        it { is_expected.to compile.and_raise_error(%r{mutually exclusive}) }
      end

      context 'with ensure => present and a source' do
        let(:params) { { 'ensure' => 'present', 'source' => 'puppet:///modules/x/y/' } }

        it { is_expected.to compile.and_raise_error(%r{needs an explicit version}) }
      end

      context 'with ensure => present and no repository' do
        let(:params) { { 'ensure' => 'present' } }

        it { is_expected.to compile.and_raise_error(%r{needs a 'repository'}) }
      end

      context 'with ensure => latest' do
        let(:params) { { 'ensure' => 'latest', 'repository' => 'PSGallery' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'ensure'}) }
      end

      # Every value below reaches a single-quoted PowerShell string in the
      # generated Exec, so the type system is what stops the string from being
      # closed early. The Execs run as the agent account, i.e. SYSTEM.
      context 'with a repository that tries to break out of the quoted string' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => "PSGallery'; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'repository'}) }
      end

      context 'with a repository holding a path separator' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery\\..\\x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'repository'}) }
      end

      context 'with a modulename holding an apostrophe' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'modulename' => "Evil'; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'modulename'}) }
      end

      context 'with a modulename that is the parent directory' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'modulename' => '..' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'modulename'}) }
      end

      # Repository names in the field carry dots, dashes and underscores.
      context 'with a punctuated but legitimate repository name' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'Internal_Repo-nuget.local' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_exec('windowspowershell install ExampleModule').with_command(%r{-Repository 'Internal_Repo-nuget\.local'}) }
      end

      context 'with two modules sharing a modulename under different titles' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'modulename' => 'Shared' } }
        let(:pre_condition) do
          super() + <<~PUPPET
            windowspowershell::external_module { 'OtherTitle':
              ensure     => '3.0.0',
              repository => 'PSGallery',
              modulename => 'Shared',
            }
          PUPPET
        end

        # Regression: Exec titles are keyed on the resource title, not the
        # modulename, so two resources sharing a modulename no longer collide
        # on a duplicate Exec declaration.
        it { is_expected.to compile.with_all_deps }

        it 'declares a distinct install Exec per resource title' do
          is_expected.to contain_exec('windowspowershell install ExampleModule')
          is_expected.to contain_exec('windowspowershell install OtherTitle')
        end
      end

      context 'logs the PowerShell output on failure' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }

        it 'sets logoutput => on_failure on every Exec it declares' do
          is_expected.to contain_exec('windowspowershell install ExampleModule').with_logoutput('on_failure')
          is_expected.to contain_exec('windowspowershell purge other versions of ExampleModule').with_logoutput('on_failure')
        end
      end

      context 'with ensure => absent, logs on failure' do
        let(:params) { { 'ensure' => 'absent' } }

        it { is_expected.to contain_exec('windowspowershell uninstall ExampleModule').with_logoutput('on_failure') }
      end

      context 'with two modules from the same repository' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:pre_condition) do
          super() + <<~PUPPET
            windowspowershell::external_module { 'OtherModule':
              ensure     => '1.0.0',
              repository => 'PSGallery',
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'bootstraps NuGet only once' do
          expect(catalogue.resources.count { |r| r.type == 'Exec' && r.title.include?('nuget') }).to eq(1)
        end
      end
    end
  end

  context 'on a non-Windows node' do
    let(:facts) { { 'os' => { 'family' => 'RedHat', 'name' => 'RedHat' } } }
    let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }

    it { is_expected.to compile.with_all_deps }

    it 'declares nothing at all' do
      expect(catalogue.resources.select { |r| %w[File Exec].include?(r.type) }).to be_empty
      is_expected.not_to contain_class('windowspowershell::psget')
    end

    context 'with a contradictory backend' do
      let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'source' => 'puppet:///modules/x/y/' } }

      it { is_expected.to compile.and_raise_error(%r{mutually exclusive}) }
    end
  end
end
