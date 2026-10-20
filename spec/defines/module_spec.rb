require 'spec_helper'
require 'digest'

describe 'windowspowershell::module' do
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

      it 'writes the module version into the manifest' do
        ['windowspowershell create-manifest Acme', 'windowspowershell update-manifest Acme'].each do |exec_name|
          is_expected.to contain_exec(exec_name).with_command(%r{-ModuleVersion '1\.0'})
        end
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

      it 'purges the other versions after unblocking' do
        is_expected.to contain_exec('windowspowershell purge other in-house versions of Acme').
          with_command(%r{\$pinned = '1\.0'}).
          with_command(%r{-as \[version\]}).
          with_unless(%r{\$pinned = '1\.0'}).
          with_unless(%r{-as \[version\]}).
          with_provider('powershell').
          with_timeout(300).
          with_logoutput('on_failure').
          that_requires('Exec[windowspowershell unblock-files Acme]')
      end

      it 'runs the purge after the manifest refresh' do
        is_expected.to contain_exec('windowspowershell purge other in-house versions of Acme').
          that_requires('Exec[windowspowershell update-manifest Acme]')
      end

      context 'with an external_module sharing the module identity' do
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::external_module { 'Acme':
              ensure     => '1.0',
              repository => 'PSGallery',
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'keeps the in-house and external purge Execs under distinct titles' do
          is_expected.to contain_exec('windowspowershell purge other in-house versions of Acme')
          is_expected.to contain_exec('windowspowershell purge other versions of Acme')
        end
      end

      context 'with purge_versions => false' do
        let(:params) { { 'purge_versions' => false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_exec('windowspowershell purge other in-house versions of Acme') }
      end

      context 'with a non-default version' do
        let(:params) { { 'version' => '2.3' } }

        it 'purges every version folder except the configured one' do
          is_expected.to contain_exec('windowspowershell purge other in-house versions of Acme').
            with_command(%r{\$pinned = '2\.3'}).
            with_command(%r{-as \[version\]}).
            with_unless(%r{\$pinned = '2\.3'}).
            with_unless(%r{-as \[version\]})
        end

        # Numeric equivalence is shared with external_module on purpose: pin
        # 2.3 also keeps a 2.3.0 folder, missing segments counting as zero,
        # while a folder that does not parse as [version] is kept, never
        # purged.
        it 'compares versions numerically, so a 2.3.0 folder counts as the pinned 2.3' do
          is_expected.to contain_exec('windowspowershell purge other in-house versions of Acme').
            with_command(%r{\$_\.Name -eq \$pinned}).
            with_command(%r{\$dirAs\.Major -eq \$pinnedAs\.Major}).
            with_command(%r{\$dirBuild -eq \$pinnedBuild}).
            with_command(%r{\$dirRevision -eq \$pinnedRevision}).
            with_command(%r{if \(\$null -eq \$dirAs\) \{ \$false \}}).
            with_unless(%r{\$_\.Name -eq \$pinned}).
            with_unless(%r{\$dirAs\.Major -eq \$pinnedAs\.Major}).
            with_unless(%r{\$dirBuild -eq \$pinnedBuild}).
            with_unless(%r{\$dirRevision -eq \$pinnedRevision}).
            with_unless(%r{if \(\$null -eq \$dirAs\) \{ \$false \}})
        end
      end

      it 'declares the refresh-only unblock-files exec over the module tree' do
        is_expected.to contain_exec('windowspowershell unblock-files Acme').with(
          'refreshonly' => true,
          'provider' => 'powershell',
          'logoutput' => 'on_failure'
        )
        is_expected.to contain_exec('windowspowershell unblock-files Acme').
          with_command(%r{Get-ChildItem -LiteralPath 'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\\1\.0' -Recurse -File \| Unblock-File})
      end

      it 'declares a self-heal manifest exec gated on the manifest file' do
        is_expected.to contain_exec('windowspowershell create-manifest Acme').with(
          'creates' => 'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\\1.0\\Acme.psd1',
          'provider' => 'powershell'
        )
        is_expected.not_to contain_exec('windowspowershell create-manifest Acme').with_refreshonly(true)
      end

      # A refresh-only Exec never runs on a change of its own `command`, so the
      # manifest parameters are mirrored in a managed witness file that does
      # notify it (issue #45).
      describe 'manifest parameters witness' do
        let(:witness) { "#{modules}\\Acme\\1.0\\.manifest-params" }

        it 'is a managed file inside the version folder' do
          is_expected.to contain_file(witness).with_ensure('file').that_requires("File[#{modules}\\Acme\\1.0]")
        end

        it 'notifies the manifest refresh and the unblock' do
          is_expected.to contain_file(witness).
            that_notifies('Exec[windowspowershell update-manifest Acme]').
            that_notifies('Exec[windowspowershell unblock-files Acme]')
        end

        it 'is deployed after the root module and before the manifest build' do
          is_expected.to contain_file(witness).
            that_requires("File[#{modules}\\Acme\\1.0\\Acme.psm1]").
            that_comes_before('Exec[windowspowershell create-manifest Acme]')
        end

        it 'holds the hash of the command that builds the manifest' do
          command = catalogue.resource('Exec', 'windowspowershell update-manifest Acme')[:command]
          expect(catalogue.resource('File', witness)[:content]).to include(Digest::SHA256.hexdigest(command))
        end

        context 'with only the author changed' do
          let(:params) { { 'author' => 'Platform Team' } }

          it 'changes the witness content, so the manifest is regenerated' do
            command = catalogue.resource('Exec', 'windowspowershell update-manifest Acme')[:command]
            default_command = command.sub("-Author 'Platform Team'", "-Author 'Unknown'")
            content = catalogue.resource('File', witness)[:content]

            expect(default_command).not_to eq(command)
            expect(content).to include(Digest::SHA256.hexdigest(command))
            expect(content).not_to include(Digest::SHA256.hexdigest(default_command))
            is_expected.to contain_file(witness).that_notifies('Exec[windowspowershell update-manifest Acme]')
          end
        end

        context 'with only the companyname changed' do
          let(:params) { { 'companyname' => 'Acme Corp' } }

          it 'changes the witness content, so the manifest is regenerated' do
            command = catalogue.resource('Exec', 'windowspowershell update-manifest Acme')[:command]
            default_command = command.sub("-CompanyName 'Acme Corp'", "-CompanyName 'Unknown'")
            content = catalogue.resource('File', witness)[:content]

            expect(default_command).not_to eq(command)
            expect(content).to include(Digest::SHA256.hexdigest(command))
            expect(content).not_to include(Digest::SHA256.hexdigest(default_command))
          end
        end
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

      # The GUID is the module's identity: it is derived from the name alone
      # (UUID v5 in the DNS namespace), so bumping `version` never changes it.
      it 'derives the GUID from the module name alone' do
        ['windowspowershell create-manifest Acme', 'windowspowershell update-manifest Acme'].each do |exec_name|
          is_expected.to contain_exec(exec_name).with_command(%r{-Guid '9b21c097-413c-58e7-bf14-3b9b5b812749'})
        end
      end

      it 'scans only the Functions directory when building the manifest' do
        is_expected.to contain_exec('windowspowershell update-manifest Acme').
          with_command(%r{\$functionsPath\s*=\s*'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\\1\.0\\Functions'}).
          with_command(%r{Get-ChildItem -LiteralPath \$functionsPath -Recurse -File \|\s+Where-Object \{ \$_\.Extension -in '\.ps1', '\.psm1' \}})
      end

      it 'declares the root module only as -RootModule, not from the scan' do
        is_expected.to contain_exec('windowspowershell update-manifest Acme').
          with_command(%r{-RootModule "\$\{moduleName\}\.psm1"})
      end

      it 'imports the module from the Windows PowerShell profiles by default' do
        [
          'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1',
          'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1',
        ].each do |profile|
          is_expected.to contain_concat_fragment("windowspowershell import Acme in #{profile}").
            with_target(profile).
            with_order('50').
            with_content(%r{Import-Module 'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\\1\.0\\Acme\.psd1'})
        end
      end

      # A broken module must leave a trace in the session instead of being
      # swallowed: the import is a terminating error caught to a warning, and
      # the session keeps starting.
      it 'warns when the profile import fails instead of failing silently' do
        profile = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
        fragment = catalogue.resource('Concat::Fragment', "windowspowershell import Acme in #{profile}")
        expect(fragment[:content]).to match(%r{-ErrorAction Stop})
        expect(fragment[:content]).to match(%r{catch \{\s*Write-Warning })
        expect(fragment[:content]).not_to match(%r{SilentlyContinue})
      end

      context 'with PowerShell 7 installed' do
        let(:facts) { os_facts.merge('powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' }) }

        it 'adds an Import-Module fragment to the pwsh profile' do
          profile = 'C:\Program Files\PowerShell\7\profile.ps1'
          is_expected.to contain_concat_fragment("windowspowershell import Acme in #{profile}").
            with_target(profile).
            with_order('50').
            with_content(%r{Import-Module 'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\\1\.0\\Acme\.psd1'})
        end
      end

      context 'with import_in_profile => false' do
        let(:params) { { 'import_in_profile' => false } }

        it 'adds no Import-Module fragment to the profiles' do
          [
            'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1',
            'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\profile.ps1',
          ].each do |profile|
            is_expected.not_to contain_concat_fragment("windowspowershell import Acme in #{profile}")
          end
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

        it 'keeps the same GUID as under the default version' do
          ['windowspowershell create-manifest Acme', 'windowspowershell update-manifest Acme'].each do |exec_name|
            is_expected.to contain_exec(exec_name).with_command(%r{-Guid '9b21c097-413c-58e7-bf14-3b9b5b812749'})
          end
        end

        it 'writes the custom version into the manifest' do
          is_expected.to contain_exec('windowspowershell update-manifest Acme').
            with_command(%r{-ModuleVersion '2\.3'})
        end

        # The folder and the manifest have to agree: the bug this covers was a
        # module installed under ...\Acme\2.3\ declaring ModuleVersion 0.0.1.
        it 'keeps the folder version and the manifest version in step' do
          is_expected.to contain_file("#{modules}\\Acme\\2.3").with_ensure('directory')
          is_expected.to contain_exec('windowspowershell update-manifest Acme').
            with_command(%r{-ModuleVersion '2\.3'})
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

      # A module name may legally hold `[` and `]` (issue #15). PowerShell's
      # -Path reads those as a wildcard character class, so the unblock Exec
      # and the Functions scan have to use -LiteralPath to reach the tree.
      context 'with a title holding brackets' do
        let(:title) { 'Acme[1]' }

        it { is_expected.to compile.with_all_deps }

        it 'unblocks the bracketed module tree with -LiteralPath' do
          is_expected.to contain_exec('windowspowershell unblock-files Acme[1]').
            with_command(%r{Get-ChildItem -LiteralPath 'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\[1\]\\1\.0' -Recurse -File \| Unblock-File})
        end

        it 'scans the bracketed Functions directory with -LiteralPath' do
          is_expected.to contain_exec('windowspowershell update-manifest Acme[1]').
            with_command(%r{\$functionsPath\s*=\s*'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme\[1\]\\1\.0\\Functions'}).
            with_command(%r{Get-ChildItem -LiteralPath \$functionsPath -Recurse -File \|\s+Where-Object \{ \$_\.Extension -in '\.ps1', '\.psm1' \}})
        end

        it 'still creates the bracketed manifest under the version folder' do
          is_expected.to contain_exec('windowspowershell create-manifest Acme[1]').
            with('creates' => 'C:\\Program Files\\WindowsPowerShell\\Modules\\Acme[1]\\1.0\\Acme[1].psd1')
        end

        it 'purges the bracketed tree by literal directory path, keeping the version' do
          is_expected.to contain_exec('windowspowershell purge other in-house versions of Acme[1]').
            with_command(%r{Get-ChildItem -LiteralPath \$moduleDir -Directory}).
            with_command(%r{\$pinned = '1\.0'}).
            with_command(%r{-as \[version\]}).
            with_unless(%r{Get-ChildItem -LiteralPath \$moduleDir -Directory}).
            with_unless(%r{\$pinned = '1\.0'}).
            with_unless(%r{-as \[version\]})
        end
      end

      context 'with a version that is not a version' do
        let(:params) { { 'version' => "1.0'; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'version'}) }
      end

      # A single number consists only of digits, so it slips past the loose
      # Windowspowershell::Version type, but PowerShell's `[version]` type,
      # which New-ModuleManifest -ModuleVersion casts to, requires a major and
      # a minor version. Reject it at compile time rather than at Exec runtime.
      context 'with a version that has only one component' do
        let(:params) { { 'version' => '1' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'version' expects a match for Windowspowershell::Moduleversion}) }
      end

      context 'with an author holding an apostrophe' do
        let(:params) { { 'author' => "Evil'; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'author'}) }
      end

      context 'with a companyname holding an apostrophe' do
        let(:params) { { 'companyname' => "Evil'; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'companyname'}) }
      end

      # PowerShell treats U+2018 to U+201B as single-quote characters too, so a
      # typographic quote ends the generated string just like an apostrophe.
      context 'with an author holding a typographic single quote' do
        let(:params) { { 'author' => "Platform Team\u2019; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'author'}) }
      end

      context 'with a companyname holding a typographic single quote' do
        let(:params) { { 'companyname' => "Evil\u2018; calc.exe #" } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'companyname'}) }
      end

      context 'with a title holding a typographic single quote' do
        let(:title) { "Evil\u2019; calc.exe #" }

        it { is_expected.to compile.and_raise_error(%r{title expects a match}) }
      end

      # A company name is free text, not a path component: spaces and dots
      # have to keep working.
      context 'with a company name holding spaces and a dot' do
        let(:params) { { 'companyname' => 'Acme S.A.S.' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_exec('windowspowershell update-manifest Acme').with_command(%r{-CompanyName 'Acme S\.A\.S\.'}) }
      end

      context 'with two modules declared, each one self-contained' do
        let(:pre_condition) { "windowspowershell::module { 'OtherModule': }" }

        it { is_expected.to compile.with_all_deps }

        it 'declares independent trees and Execs for each' do
          is_expected.to contain_file("#{modules}\\Acme\\1.0")
          is_expected.to contain_file("#{modules}\\OtherModule\\1.0")
          is_expected.to contain_exec('windowspowershell update-manifest Acme')
          is_expected.to contain_exec('windowspowershell update-manifest OtherModule')
        end

        it 'gives each module its own GUID' do
          is_expected.to contain_exec('windowspowershell update-manifest OtherModule').
            with_command(%r{-Guid 'e7588131-a72c-5d75-86e1-4aea75519daa'})
          is_expected.to contain_exec('windowspowershell update-manifest Acme').
            with_command(%r{-Guid '9b21c097-413c-58e7-bf14-3b9b5b812749'})
        end

        # Regression test for issue #12: the profile Import-Module lines used
        # to overwrite each other through a File collector, so only one
        # module survived in the profile. Each module now owns its fragment.
        it 'keeps an Import-Module fragment for each module instead of overwriting' do
          profile = 'C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1'
          is_expected.to contain_concat_fragment("windowspowershell import Acme in #{profile}").
            with_target(profile).
            with_order('50').
            with_content(%r{Acme\.psd1})
          is_expected.to contain_concat_fragment("windowspowershell import OtherModule in #{profile}").
            with_target(profile).
            with_order('50').
            with_content(%r{OtherModule\.psd1})
        end
      end

      # A bracketed module_root (issue #15) reaches both Execs, whose commands
      # must keep the brackets literal for the paths to resolve.
      context 'with a module_root holding brackets' do
        let(:pre_condition) { "class { 'windowspowershell': module_root => 'C:\\Modules[1]' }" }

        it { is_expected.to compile.with_all_deps }

        it 'unblocks the bracketed module tree with -LiteralPath' do
          is_expected.to contain_exec('windowspowershell unblock-files Acme').
            with_command(%r{Get-ChildItem -LiteralPath 'C:\\Modules\[1\]\\Acme\\1\.0' -Recurse -File \| Unblock-File})
        end

        it 'scans the bracketed Functions directory with -LiteralPath' do
          is_expected.to contain_exec('windowspowershell update-manifest Acme').
            with_command(%r{\$functionsPath\s*=\s*'C:\\Modules\[1\]\\Acme\\1\.0\\Functions'}).
            with_command(%r{Get-ChildItem -LiteralPath \$functionsPath -Recurse -File \|\s+Where-Object \{ \$_\.Extension -in '\.ps1', '\.psm1' \}})
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
      expect(catalogue.resources.select { |r| %w[File Exec Concat Concat::Fragment].include?(r.type) }).to be_empty
      is_expected.not_to contain_exec('windowspowershell purge other in-house versions of Acme')
    end
  end
end
