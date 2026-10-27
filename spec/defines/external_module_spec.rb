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
            with_unless(%r{Get-PackageProvider -Name NuGet}).
            with_unless(%r{2\.8\.5\.201})
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
            with_unless(%r{\$pinned = '2\.1\.0'}).
            with_unless(%r{Test-PinnedVersionMatch}).
            with_unless(%r{Get-NormalizedVersion})
          expect(unless_of('windowspowershell install ExampleModule')).not_to match(%r{Get-Module -ListAvailable})
        end

        # Issue #106: an interrupted install leaves an empty or partial version
        # folder behind. The folder name alone must not satisfy the check: only
        # a candidate whose <modulename>.psd1 passes Test-ModuleManifest counts.
        it 'requires a valid manifest so a partial folder reinstalls' do
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$moduleName = 'ExampleModule'})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{function Test-ModuleHealthy})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Join-Path -Path \$DirPath -ChildPath})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Test-Path -LiteralPath \$psd1})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Test-ModuleManifest -Path})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Where-Object \{ Test-ModuleHealthy})
        end

        it 'treats a normalised folder as the pinned version' do
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{function Test-PinnedVersionMatch})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$dirAs = Get-NormalizedVersion \$DirName})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$dirAs\.Major -eq \$pinnedAs\.Major})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$dirBuild -eq \$pinnedBuild})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$dirRevision -eq \$pinnedRevision})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Where-Object \{ Test-PinnedVersionMatch})
        end

        it 'purges the other versions after installing' do
          is_expected.to contain_exec('windowspowershell purge other versions of ExampleModule').
            with_command(%r{\$pinned = '2\.1\.0'}).
            with_command(%r{Test-IsExtraVersion}).
            that_requires('Exec[windowspowershell install ExampleModule]')
        end

        context 'with a short pinned version' do
          let(:params) { { 'ensure' => '2.1', 'repository' => 'PSGallery' } }

          it { is_expected.to compile.with_all_deps }

          it 'keeps the normalised folder instead of reinstalling' do
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$pinned = '2\.1'})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Test-PinnedVersionMatch})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Get-NormalizedVersion})
          end

          it 'keeps the normalised folder instead of purging it' do
            expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$pinned = '2\.1'})
            expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{Test-IsExtraVersion})
          end

          it 'requires a valid manifest on the normalised folder too (issue #106)' do
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$moduleName = 'ExampleModule'})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Test-Path -LiteralPath \$psd1})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Test-ModuleManifest -Path})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\.psd1})
          end
        end

        context 'with a single-component pinned version' do
          let(:params) { { 'ensure' => '2', 'repository' => 'PSGallery' } }

          it { is_expected.to compile.with_all_deps }

          it 'normalises the pin before casting so folder 2.0 counts as installed' do
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$pinned = '2'})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{function Get-NormalizedVersion})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{-match '\^\\d\+\$'})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\+ '\.0'})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$pinnedAs = Get-NormalizedVersion \$pinned})
          end

          it 'normalises the pin before casting so folder 2.0 is kept by the purge' do
            expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{function Get-NormalizedVersion})
            expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$pinnedAs = Get-NormalizedVersion \$pinned})
            expect(unless_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$pinnedAs = Get-NormalizedVersion \$pinned})
          end
        end

        # Behaviour table, negative row: pin 2.2 against folder 2.2.1.5. All
        # four [version] components are compared with missing segments
        # treated as zero, so a folder that differs in build or revision
        # still counts as a different version: the install check misses it
        # and the purge removes it.
        context 'with a pinned version that differs in build from the installed folder' do
          let(:params) { { 'ensure' => '2.2', 'repository' => 'PSGallery' } }

          it { is_expected.to compile.with_all_deps }

          it 'compares build and revision numerically, so 2.2.1.5 counts as different from 2.2' do
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$pinned = '2\.2'})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Test-PinnedVersionMatch})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$dirBuild -eq \$pinnedBuild})
            expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$dirRevision -eq \$pinnedRevision})
            expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$pinned = '2\.2'})
            expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{Test-IsExtraVersion})
            expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$dirBuild -eq \$pinnedBuild})
            expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$dirRevision -eq \$pinnedRevision})
            expect(unless_of('windowspowershell purge other versions of ExampleModule')).to match(%r{Test-IsExtraVersion})
            expect(unless_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$dirBuild -eq \$pinnedBuild})
            expect(unless_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$dirRevision -eq \$pinnedRevision})
          end
        end

        it 'keeps a non-version directory instead of purging it' do
          expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{function Test-IsExtraVersion})
          expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{if \(\$null -eq \$dirAs\) \{ return \$false \}})
        end

        it 'keeps a non-version directory in the install check' do
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{function Test-PinnedVersionMatch})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{if \(\$null -eq \$dirAs\) \{ return \$false \}})
        end

        it 'keeps a non-version directory in the purge check' do
          expect(unless_of('windowspowershell purge other versions of ExampleModule')).to match(%r{function Test-IsExtraVersion})
          expect(unless_of('windowspowershell purge other versions of ExampleModule')).to match(%r{if \(\$null -eq \$dirAs\) \{ return \$false \}})
        end

        it 'declares no file resource for a repository-backed module' do
          is_expected.not_to contain_file("#{modules}\\ExampleModule")
        end
      end

      context 'from a repository, without a proxy' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }

        it 'passes no -Proxy at all' do
          expect(command_of('windowspowershell install ExampleModule')).not_to match(%r{-Proxy})
          expect(command_of('windowspowershell install nuget provider')).not_to match(%r{-Proxy})
        end

        it 'sets no environment on the Execs' do
          expect(catalogue.resource('Exec', 'windowspowershell install ExampleModule')[:environment]).to be_nil
          expect(catalogue.resource('Exec', 'windowspowershell install nuget provider')[:environment]).to be_nil
        end
      end

      context 'from a repository, with a proxy on the class' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:pre_condition) { "class { 'windowspowershell': proxy => 'http://172.18.69.200:8080' }" }

        it { is_expected.to compile.with_all_deps }

        it 'passes the proxy to Install-Module and to the NuGet bootstrap' do
          is_expected.to contain_exec('windowspowershell install ExampleModule').
            with_command(%r{-Proxy 'http://172\.18\.69\.200:8080'})
          is_expected.to contain_exec('windowspowershell install nuget provider').
            with_command(%r{-Proxy 'http://172\.18\.69\.200:8080'})
        end
      end

      context 'from a repository, with credentials embedded in the proxy URL (removed in v2.0)' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:pre_condition) { "class { 'windowspowershell': proxy => 'http://user:pass@172.18.69.200:8080' }" }

        it { is_expected.to compile.and_raise_error(%r{parameter 'proxy'}) }
      end

      context 'from a repository, with proxy_credential on the class' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:pre_condition) do
          <<~PUPPET
            class { 'windowspowershell':
              proxy            => 'http://proxy.example.net:3128',
              proxy_credential => {
                username => 'svc-puppet',
                password => Sensitive('s3cret-pw'),
              },
            }
          PUPPET
        end

        install_titles = ['windowspowershell install ExampleModule', 'windowspowershell install nuget provider']

        def environment_of(title)
          environment = catalogue.resource('Exec', title)[:environment]
          environment.respond_to?(:unwrap) ? environment.unwrap : environment
        end

        it { is_expected.to compile.with_all_deps }

        it 'passes -ProxyCredential next to -Proxy on Install-Module and on the NuGet bootstrap' do
          is_expected.to contain_exec('windowspowershell install ExampleModule').
            with_command(%r{-Proxy 'http://proxy\.example\.net:3128'}).
            with_command(%r{-ProxyCredential \$proxyCredential})
          is_expected.to contain_exec('windowspowershell install nuget provider').
            with_command(%r{-Proxy 'http://proxy\.example\.net:3128'}).
            with_command(%r{-ProxyCredential \$proxyCredential})
        end

        it 'reads the credentials from the environment, not from the script text' do
          install_titles.each do |title|
            expect(command_of(title)).to match(%r{\$env:WPS_PROXY_USER})
            expect(command_of(title)).to match(%r{\$env:WPS_PROXY_PASSWORD})
          end
        end

        it 'writes neither the password nor the username in any command or unless' do
          install_titles.each do |title|
            expect(command_of(title)).not_to match(%r{s3cret-pw|svc-puppet})
            expect(unless_of(title)).not_to match(%r{s3cret-pw|svc-puppet})
          end
        end

        it 'hands the credentials to both Execs through their environment' do
          install_titles.each do |title|
            expect(environment_of(title)).to contain_exactly('WPS_PROXY_USER=svc-puppet', 'WPS_PROXY_PASSWORD=s3cret-pw')
          end
        end

        # Puppet unwraps the Sensitive value on the resource and flags the
        # parameter instead, which is what redacts it from reports and logs.
        it 'flags the environment as a sensitive parameter so that Puppet redacts it' do
          install_titles.each do |title|
            expect(catalogue.resource('Exec', title).sensitive_parameters).to include(:environment)
          end
        end

        it 'does not flag the command as sensitive' do
          install_titles.each do |title|
            expect(catalogue.resource('Exec', title).sensitive_parameters).not_to include(:command)
          end
        end

        it 'leaves the other Execs without credentials' do
          expect(catalogue.resource('Exec', 'windowspowershell purge other versions of ExampleModule')[:environment]).to be_nil
        end
      end

      context 'from a repository, with proxy_credential but no proxy' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:pre_condition) do
          "class { 'windowspowershell': proxy_credential => { username => 'u', password => Sensitive('p') } }"
        end

        it { is_expected.to compile.and_raise_error(%r{'proxy_credential' needs 'proxy'}) }
      end

      context 'from a repository, with proxy_credential and credentials embedded in the proxy URL' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:pre_condition) do
          <<~PUPPET
            class { 'windowspowershell':
              proxy            => 'http://user:pass@proxy.example.net:3128',
              proxy_credential => { username => 'u', password => Sensitive('p') },
            }
          PUPPET
        end

        it { is_expected.to compile.and_raise_error(%r{parameter 'proxy'}) }
      end

      context 'from a repository, with a plain-string password in proxy_credential' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:pre_condition) do
          <<~PUPPET
            class { 'windowspowershell':
              proxy            => 'http://proxy.example.net:3128',
              proxy_credential => { username => 'u', password => 'plain' },
            }
          PUPPET
        end

        it { is_expected.to compile.and_raise_error(%r{parameter 'proxy_credential'}) }
      end

      context 'from a repository, with a stray http_proxy fact' do
        let(:facts) { os_facts.merge('http_proxy' => { 'host' => '172.18.69.200', 'port' => '8080' }) }
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }

        it { is_expected.to compile.with_all_deps }

        it 'ignores the fact and passes no -Proxy at all' do
          expect(command_of('windowspowershell install ExampleModule')).not_to match(%r{-Proxy})
          expect(command_of('windowspowershell install nuget provider')).not_to match(%r{-Proxy})
        end
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

        # Issue #55: a stray folder under the module directory is not a version
        # and must not satisfy the check, or the install is blocked forever.
        # Shared helper (issue #52): the present-branch renders the partial
        # without a pin, so only Get-NormalizedVersion is defined.
        it 'only counts folders that parse as a [version]' do
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{function Get-NormalizedVersion})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$null -ne \(Get-NormalizedVersion})
        end

        # Issue #106: same manifest gate as the pinned branch -- an empty or
        # partial folder of any version must not satisfy ensure => present.
        it 'requires a valid manifest so a partial folder still installs' do
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$moduleName = 'ExampleModule'})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{function Test-ModuleHealthy})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Test-Path -LiteralPath \$psd1})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Test-ModuleManifest -Path})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\.psd1})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Where-Object \{ Test-ModuleHealthy})
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

      # Install-Module reads -Name as a wildcard (issue #73), while a module
      # name may legally hold brackets (issue #15): escape them so the
      # literal module is installed.
      context 'from a repository, with a modulename holding wildcards' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'modulename' => 'Bracket[Beta]' } }

        it { is_expected.to compile.with_all_deps }

        it 'escapes the -Name wildcards in the install command' do
          is_expected.to contain_exec('windowspowershell install ExampleModule').
            with_command(%r{Install-Module -Name 'Bracket`\[Beta`\]'}).
            with_command(%r{-RequiredVersion '2\.1\.0'})
        end

        it 'excludes wildcard names from the manifest parse but still requires the psd1 (issue #106)' do
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$moduleName = 'Bracket\[Beta\]'})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{Test-Path -LiteralPath \$psd1})
          expect(unless_of('windowspowershell install ExampleModule')).to match(%r{\$moduleName -match})
        end
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

        it 'keeps the literal 4-segment folder and compares versions numerically' do
          expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$pinned = '2\.2\.1\.5'})
          expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{Test-IsExtraVersion})
          expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{Get-NormalizedVersion})
          expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$dirBuild -eq \$pinnedBuild})
          expect(command_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$dirRevision -eq \$pinnedRevision})
          expect(unless_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$pinned = '2\.2\.1\.5'})
          expect(unless_of('windowspowershell purge other versions of ExampleModule')).to match(%r{Test-IsExtraVersion})
          expect(unless_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$dirBuild -eq \$pinnedBuild})
          expect(unless_of('windowspowershell purge other versions of ExampleModule')).to match(%r{\$dirRevision -eq \$pinnedRevision})
        end
      end

      context 'with a version but neither repository nor source' do
        let(:params) { { 'ensure' => '2.1.0' } }

        it { is_expected.to compile.and_raise_error(%r{needs a 'repository' or a 'source'}) }
      end

      # Install-Module -Scope AllUsers ignores a custom module_root (issue #85):
      # the check would miss the module and reinstall on every run.
      context 'from a repository with a custom module_root' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:pre_condition) { "class { 'windowspowershell': module_root => 'C:\\wps-custom\\Modules' }" }

        it { is_expected.to compile.and_raise_error(%r{needs the default 'module_root'}) }
      end

      context 'from a source with a custom module_root' do
        let(:params) { { 'ensure' => '2.1.0', 'source' => 'puppet:///modules/x/y/' } }
        let(:pre_condition) { "class { 'windowspowershell': module_root => 'C:\\wps-custom\\Modules' }" }

        it { is_expected.to compile.with_all_deps }

        it 'copies into the custom root' do
          is_expected.to contain_file('C:\\wps-custom\\Modules\\ExampleModule\\2.1.0')
        end
      end

      context 'from a source with a trailing-separator custom module_root (issue #111)' do
        let(:params) { { 'ensure' => '2.1.0', 'source' => 'puppet:///modules/x/y/' } }
        let(:pre_condition) { "class { 'windowspowershell': module_root => 'C:\\\\wps-custom\\\\Modules\\\\' }" }

        it { is_expected.to compile.with_all_deps }

        it 'copies into the stripped custom root, with no doubled separator' do
          is_expected.to contain_file('C:\wps-custom\Modules\ExampleModule\2.1.0')
          is_expected.not_to contain_file('C:\wps-custom\Modules\\\\ExampleModule')
        end
      end

      context 'from a repository with a trailing separator on the default module_root (issue #111)' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery' } }
        let(:pre_condition) { "class { 'windowspowershell': module_root => 'C:\\\\Program Files\\\\WindowsPowerShell\\\\Modules\\\\' }" }

        it { is_expected.to compile.with_all_deps }
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

      # Uninstall-Module and Get-InstalledModule read -Name as a wildcard
      # too (issue #73): escape it so the literal module is removed.
      context 'with ensure => absent and a modulename holding wildcards' do
        let(:params) { { 'ensure' => 'absent', 'modulename' => 'Bracket[Beta]' } }

        it { is_expected.to compile.with_all_deps }

        it 'escapes the -Name wildcards when unregistering and checking' do
          is_expected.to contain_exec('windowspowershell uninstall ExampleModule').
            with_command(%r{Uninstall-Module -Name 'Bracket`\[Beta`\]' -AllVersions -Force})
          expect(unless_of('windowspowershell uninstall ExampleModule')).to match(%r{Get-InstalledModule -Name 'Bracket`\[Beta`\]' -AllVersions})
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

      # Issue #88: PowerShellGet and PackageManagement ship with Windows and
      # Install-Module stops working without them. Only `absent` is refused:
      # installing or upgrading them stays legitimate.
      context 'with ensure => absent and a protected system modulename' do
        let(:params) { { 'ensure' => 'absent', 'modulename' => 'PowerShellGet' } }

        it { is_expected.to compile.and_raise_error(%r{refusing to remove protected system module}) }
      end

      context 'with ensure => absent and a protected system modulename in another case' do
        let(:params) { { 'ensure' => 'absent', 'modulename' => 'packagemanagement' } }

        it { is_expected.to compile.and_raise_error(%r{refusing to remove protected system module}) }
      end

      context 'with a version pinned and a protected system modulename' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'modulename' => 'PowerShellGet' } }

        it { is_expected.to compile.with_all_deps }
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

      # Each component is parsed as an Int32 by System.Version, so ten digits
      # would overflow at Exec runtime: refused at compile time instead.
      context 'with a version component that overflows Int32' do
        let(:params) { { 'ensure' => '9999999999.0', 'repository' => 'PSGallery' } }

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

      context 'with a modulename holding a typographic single quote' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'modulename' => "Evil\u2019; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'modulename'}) }
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

      context 'with import_in_profile => true' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'import_in_profile' => true } }
        let(:pre_condition) do
          super().dup << <<~PUPPET
            class { 'windowspowershell': manage_profiles => true }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'adds one fragment per managed profile, pinned to the version' do
          [
            'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1',
            'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1',
          ].each do |profile|
            is_expected.to contain_concat_fragment("windowspowershell import external ExampleModule in #{profile}").
              with_target(profile).
              with_order('60').
              with_content(%r{Import-Module 'ExampleModule' -RequiredVersion '2\.1\.0'})
          end
        end

        it 'warns when the profile import fails instead of failing silently' do
          profile = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
          fragment = catalogue.resource('Concat::Fragment', "windowspowershell import external ExampleModule in #{profile}")
          expect(fragment[:content]).to match(%r{-ErrorAction Stop})
          expect(fragment[:content]).to match(%r{catch \{\s*Write-Warning })
          expect(fragment[:content]).not_to match(%r{SilentlyContinue})
        end
      end

      context 'with import_in_profile => true and default class parameters' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'import_in_profile' => true } }

        it { is_expected.to compile.with_all_deps }

        it 'declares no Import-Module fragment when profiles are not managed' do
          [
            'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1',
            'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1',
          ].each do |profile|
            is_expected.not_to contain_concat_fragment("windowspowershell import external ExampleModule in #{profile}")
          end
        end
      end

      # Import-Module reads -Name as a wildcard as well (issue #73), so the
      # profile fragment escapes a bracketed modulename literally.
      context 'with import_in_profile => true and a modulename holding wildcards' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'modulename' => 'Bracket[Beta]', 'import_in_profile' => true } }
        let(:pre_condition) do
          super().dup << <<~PUPPET
            class { 'windowspowershell': manage_profiles => true }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'escapes the -Name wildcards in the profile import' do
          profile = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
          is_expected.to contain_concat_fragment("windowspowershell import external ExampleModule in #{profile}").
            with_target(profile).
            with_order('60').
            with_content(%r{Import-Module 'Bracket`\[Beta`\]' -RequiredVersion '2\.1\.0'})
        end
      end

      context 'with PowerShell 7 installed and import_in_profile => true' do
        let(:facts) { os_facts.merge('powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' }) }
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'import_in_profile' => true } }
        let(:pre_condition) do
          super().dup << <<~PUPPET
            class { 'windowspowershell': manage_profiles => true }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'adds the pinned fragment to the pwsh profile' do
          profile = 'C:\Program Files\PowerShell\7\profile.ps1'
          is_expected.to contain_concat_fragment("windowspowershell import external ExampleModule in #{profile}").
            with_target(profile).
            with_order('60').
            with_content(%r{Import-Module 'ExampleModule' -RequiredVersion '2\.1\.0'})
        end
      end

      context 'with ensure => present and import_in_profile => true' do
        let(:params) { { 'ensure' => 'present', 'repository' => 'PSGallery', 'import_in_profile' => true } }
        let(:pre_condition) do
          super().dup << <<~PUPPET
            class { 'windowspowershell': manage_profiles => true }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'imports without pinning a version' do
          profile = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
          is_expected.to contain_concat_fragment("windowspowershell import external ExampleModule in #{profile}").
            with_target(profile).
            with_order('60').
            with_content(%r{Import-Module 'ExampleModule'})
          expect(catalogue.resource('Concat::Fragment', "windowspowershell import external ExampleModule in #{profile}")[:content]).not_to match(%r{-RequiredVersion})
        end
      end

      context 'with a single-component pinned version and import_in_profile => true' do
        let(:params) { { 'ensure' => '2', 'repository' => 'PSGallery', 'import_in_profile' => true } }
        let(:pre_condition) do
          super().dup << <<~PUPPET
            class { 'windowspowershell': manage_profiles => true }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        # Import-Module -RequiredVersion is typed [version], which needs at
        # least major.minor: the fragment normalises the pin to 2.0.
        it 'normalises the pin so the Import-Module line carries a valid [version]' do
          profile = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
          is_expected.to contain_concat_fragment("windowspowershell import external ExampleModule in #{profile}").
            with_content(%r{Import-Module 'ExampleModule' -RequiredVersion '2\.0'})
        end
      end

      context 'with import_in_profile and an in-house module sharing the modulename' do
        let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'modulename' => 'Acme', 'import_in_profile' => true } }
        let(:pre_condition) do
          super().dup << <<~PUPPET
            class { 'windowspowershell': manage_profiles => true }
            windowspowershell::module { 'Acme':
              import_in_profile => true,
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'keeps both fragments under distinct titles instead of colliding' do
          profile = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
          is_expected.to contain_concat_fragment("windowspowershell import Acme in #{profile}").
            with_order('50').
            with_content(%r{Acme\.psd1})
          is_expected.to contain_concat_fragment("windowspowershell import external ExampleModule in #{profile}").
            with_order('60').
            with_content(%r{Import-Module 'Acme' -RequiredVersion '2\.1\.0'})
        end
      end

      context 'with ensure => absent and import_in_profile => true' do
        let(:params) { { 'ensure' => 'absent', 'import_in_profile' => true } }

        it { is_expected.to compile.with_all_deps }

        it 'adds no import fragment (absent stays a no-op for profiles)' do
          [
            'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1',
            'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1',
          ].each do |profile|
            is_expected.not_to contain_concat_fragment("windowspowershell import external ExampleModule in #{profile}")
          end
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
      expect(catalogue.resources.select { |r| %w[File Exec Concat Concat::Fragment].include?(r.type) }).to be_empty
      is_expected.not_to contain_class('windowspowershell::psget')
    end

    context 'with a contradictory backend' do
      let(:params) { { 'ensure' => '2.1.0', 'repository' => 'PSGallery', 'source' => 'puppet:///modules/x/y/' } }

      it { is_expected.to compile.and_raise_error(%r{mutually exclusive}) }
    end

    context 'with ensure => absent and a protected system modulename' do
      let(:params) { { 'ensure' => 'absent', 'modulename' => 'PowerShellGet' } }

      it { is_expected.to compile.and_raise_error(%r{refusing to remove protected system module}) }
    end
  end
end
