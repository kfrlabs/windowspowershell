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

      context 'with a module_root holding a typographic single quote' do
        let(:params) { { 'module_root' => "C:\\x\u2019; calc.exe #" } }

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

      # A bracket is legal in the type and Windows itself allows it; PowerShell
      # only misreads it with -Path, not with the file resources here.
      context 'with a module_root holding brackets' do
        let(:params) { { 'module_root' => 'C:\\Modules[1]' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file('C:\\Modules[1]').with_ensure('directory') }
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

        it { is_expected.to compile.and_raise_error(%r{manage_pwsh_profile is true but PowerShell 7 was not detected at its default location}) }
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

        context 'with credentials embedded in the proxy URL' do
          let(:params) { { 'proxy' => 'http://user:pass@proxy.example.net:3128' } }

          it { is_expected.to compile.and_raise_error(%r{parameter 'proxy'}) }
        end

        context 'with only a username embedded in the proxy URL' do
          let(:params) { { 'proxy' => 'http://user@proxy.example.net:3128' } }

          it { is_expected.to compile.and_raise_error(%r{parameter 'proxy'}) }
        end

        context 'with an invalid proxy' do
          let(:params) { { 'proxy' => 'not a url' } }

          it { is_expected.to compile.and_raise_error(%r{parameter 'proxy'}) }
        end

        # The proxy is interpolated between single quotes in scripts the agent
        # runs as SYSTEM, so anything able to end that string is refused at
        # compile time. Stdlib::HTTPUrl alone accepts all of these.
        context 'with a proxy holding an apostrophe' do
          let(:params) { { 'proxy' => "http://proxy.example.net:3128'; calc.exe #" } }

          it { is_expected.to compile.and_raise_error(%r{parameter 'proxy'}) }
        end

        # PowerShell treats U+2018 to U+201B as single-quote characters too.
        context 'with a proxy holding a typographic single quote' do
          let(:params) { { 'proxy' => "http://proxy.example.net:3128\u2019; calc.exe #" } }

          it { is_expected.to compile.and_raise_error(%r{parameter 'proxy'}) }
        end

        context 'with a proxy holding whitespace' do
          let(:params) { { 'proxy' => 'http://proxy.example.net:3128 -Foo' } }

          it { is_expected.to compile.and_raise_error(%r{parameter 'proxy'}) }
        end

        context 'with a proxy holding a line break' do
          let(:params) { { 'proxy' => "http://proxy.example.net:3128\nCalc" } }

          it { is_expected.to compile.and_raise_error(%r{parameter 'proxy'}) }
        end

        context 'with a proxy URL carrying a trailing slash' do
          let(:params) { { 'proxy' => 'http://proxy.example.net:3128/' } }

          it { is_expected.to compile.with_all_deps }

          it 'passes the URL to the nuget bootstrap unchanged' do
            is_expected.to contain_exec('windowspowershell install nuget provider').
              with_command(%r{-Proxy 'http://proxy\.example\.net:3128/'})
          end
        end

        # Stdlib::HTTPUrl is case-insensitive on the scheme; keep it that way.
        context 'with an upper-case scheme' do
          let(:params) { { 'proxy' => 'HTTPS://proxy.example.net:3128' } }

          it { is_expected.to compile.with_all_deps }
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

      context 'with manage_pwsh_profile => true and manage_profiles => false' do
        let(:params) { { 'manage_profiles' => false, 'manage_pwsh_profile' => true } }

        it { is_expected.to compile.and_raise_error(%r{'manage_pwsh_profile' is true but 'manage_profiles' is false}) }
      end

      context 'with an in-house and an external module importing into the profile' do
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::external_module { 'ExampleModule':
              ensure            => '2.1.0',
              repository        => 'PSGallery',
              import_in_profile => true,
            }
            windowspowershell::module { 'Acme':
              import_in_profile => true,
            }
          PUPPET
        end

        it_behaves_like 'mixed in-house and external profile imports'
      end

      # Same pair declared in the reverse order (module first, external
      # second): declaration order must not change the fragment set.
      context 'with the same in-house and external modules declared in reverse order' do
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::module { 'Acme':
              import_in_profile => true,
            }
            windowspowershell::external_module { 'ExampleModule':
              ensure            => '2.1.0',
              repository        => 'PSGallery',
              import_in_profile => true,
            }
          PUPPET
        end

        it_behaves_like 'mixed in-house and external profile imports'
      end

      # Co-management (issue #31): another module, or a site profile class,
      # can add its own concat::fragment to the same targets. Those fragments
      # coexist with the header (00) and the Import-Module fragments (50, 60)
      # instead of being removed on the next run.
      context 'with an extra concat fragment from another module on the Windows PowerShell profile' do
        let(:profile) { 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1' }
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::module { 'Acme':
              import_in_profile => true,
            }
            concat::fragment { 'othermodule early alias':
              target  => '#{profile}',
              order   => '10',
              content => "Set-Alias ll Get-ChildItem\\n",
            }
            concat::fragment { 'othermodule late setting':
              target  => '#{profile}',
              order   => '70',
              content => "Set-PSReadLineOption -BellStyle None\\n",
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'keeps the extra fragments on the same concat target as the managed ones' do
          is_expected.to contain_concat(profile).with_ensure('present')
          is_expected.to contain_concat_fragment('othermodule early alias').
            with_target(profile).
            with_content(%r{Set-Alias ll Get-ChildItem})
          is_expected.to contain_concat_fragment('othermodule late setting').
            with_target(profile).
            with_content(%r{Set-PSReadLineOption -BellStyle None})
        end

        it 'keeps the header and the Import-Module fragment alongside the extras' do
          is_expected.to contain_concat_fragment("windowspowershell header #{profile}").
            with_target(profile).
            with_order('00')
          is_expected.to contain_concat_fragment("windowspowershell import Acme in #{profile}").
            with_target(profile).
            with_order('50').
            with_content(%r{Acme\.psd1})
        end

        it 'sorts the extras around the header and the imports by their order' do
          fragments = catalogue.resources.select { |r| r.type == 'Concat::Fragment' && r[:target] == profile }
          sorted = fragments.sort_by { |r| r[:order] }.map(&:title)
          expected = [
            "windowspowershell header #{profile}",
            'othermodule early alias',
            "windowspowershell import Acme in #{profile}",
            'othermodule late setting',
          ]
          expect(sorted).to eq(expected)
        end

        it 'does not leak the extra fragments into the other profile' do
          other = 'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1'
          targets = catalogue.resources.select { |r| r.type == 'Concat::Fragment' && r[:target] == other }.map(&:title)
          expect(targets).not_to include('othermodule early alias', 'othermodule late setting')
        end
      end

      # The documented pattern: extras follow `profile_paths`, so they land on
      # the PowerShell 7 profile too when it is managed.
      context 'with an extra fragment added on every managed profile through profile_paths' do
        let(:facts) { os_facts.merge('powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' }) }
        let(:pre_condition) do
          <<~PUPPET
            include windowspowershell

            if $windowspowershell::supported {
              $windowspowershell::profile_paths.each |$profile_path| {
                concat::fragment { "othermodule extras in ${profile_path}":
                  target  => $profile_path,
                  order   => '70',
                  content => "Set-Alias ll Get-ChildItem\\n",
                }
              }
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'adds the extra fragment next to the header on all three profiles' do
          [
            'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1',
            'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1',
            'C:\Program Files\PowerShell\7\profile.ps1',
          ].each do |profile|
            is_expected.to contain_concat_fragment("windowspowershell header #{profile}").with_target(profile)
            is_expected.to contain_concat_fragment("othermodule extras in #{profile}").
              with_target(profile).
              with_order('70')
          end
        end
      end

      context 'with PowerShell 7 installed and mixed imports into the pwsh profile' do
        let(:facts) { os_facts.merge('powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' }) }
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::module { 'Acme':
              import_in_profile => true,
            }
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

        it 'keeps the PSReadLine header alongside the Import-Module lines on the pwsh profile' do
          profile = 'C:\Program Files\PowerShell\7\profile.ps1'
          is_expected.to contain_concat(profile).with_ensure('present')
          is_expected.to contain_concat_fragment("windowspowershell header #{profile}").
            with_target(profile).
            with_order('00').
            with_content(%r{Set-PSReadLineOption -PredictionViewStyle ListView})
          is_expected.to contain_concat_fragment("windowspowershell import Acme in #{profile}").
            with_target(profile).
            with_content(%r{Acme\.psd1})
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

    # The documented co-management pattern must stay safe to classify on any
    # node: without the `supported` guard, the fragment would point at a concat
    # target that is only declared on Windows.
    context 'with the documented extra-fragment pattern, guarded by supported' do
      let(:pre_condition) do
        <<~PUPPET
          include windowspowershell

          if $windowspowershell::supported {
            $windowspowershell::profile_paths.each |$profile_path| {
              concat::fragment { "othermodule extras in ${profile_path}":
                target  => $profile_path,
                order   => '70',
                content => "Set-Alias ll Get-ChildItem\\n",
              }
            }
          }
        PUPPET
      end

      it { is_expected.to compile.with_all_deps }

      it 'declares no fragment' do
        expect(catalogue.resources.select { |r| r.type == 'Concat::Fragment' }).to be_empty
      end
    end
  end
end
