require 'spec_helper'

describe 'windowspowershell::script' do
  let(:title) { 'Get-Example' }
  let(:params) { { 'modulename' => 'Acme', 'content' => "Write-Output 'example'\n" } }

  functions = 'C:\Program Files\WindowsPowerShell\Modules\Acme\1.0\Functions'

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:pre_condition) { "windowspowershell::module { 'Acme': }" }

      context 'with content and no folder' do
        it { is_expected.to compile.with_all_deps }

        it 'deploys under the default version folder of the declared module' do
          is_expected.to contain_windowspowershell__module('Acme')
          is_expected.to contain_file("#{functions}\\Get-Example.ps1").
            with_ensure('file').
            with_content("Write-Output 'example'\n").
            that_notifies('Exec[windowspowershell update-manifest Acme]').
            that_notifies('Exec[windowspowershell unblock-files Acme]')
        end
      end

      context 'with an explicitly declared module overriding defaults' do
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::module { 'Acme':
              version     => '2.0',
              companyname => 'Acme Corp',
              author      => 'Platform Team',
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'deploys under the overridden version, not the define default' do
          is_expected.to contain_file('C:\Program Files\WindowsPowerShell\Modules\Acme\2.0\Functions\Get-Example.ps1')
          is_expected.not_to contain_file("#{functions}\\Get-Example.ps1")
        end
      end

      # Issue #46: a define body is evaluated after the scope that declared it,
      # so an explicit module written AFTER a script in the same scope is
      # already in the catalogue when the script resolves its version.
      context 'with an explicit module declared after another script in the same scope' do
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::script { 'Get-Early': modulename => 'Acme', content => 'x' }
            windowspowershell::module { 'Acme': version => '2.0' }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'resolves both scripts to the explicit version' do
          is_expected.to contain_file('C:\Program Files\WindowsPowerShell\Modules\Acme\2.0\Functions\Get-Early.ps1')
          is_expected.to contain_file('C:\Program Files\WindowsPowerShell\Modules\Acme\2.0\Functions\Get-Example.ps1')
          is_expected.not_to contain_file("#{functions}\\Get-Early.ps1")
        end
      end

      # The one losing order: the explicit module sits in a define nested one
      # level deeper, so the script body runs before the module is declared and
      # cannot see it. The script fails with its own message instead of building
      # a wrong version path.
      context 'with an explicit module declared from a scope evaluated after the script body' do
        let(:pre_condition) do
          <<~PUPPET
            define probe::inner { windowspowershell::module { 'Acme': version => '2.0' } }
            define probe::outer { probe::inner { 'x': } }
            probe::outer { 'y': }
          PUPPET
        end

        it { is_expected.to compile.and_raise_error(%r{module 'Acme' is not declared}) }
      end

      context 'with no module declared at all' do
        let(:pre_condition) { '' }

        it 'fails with a message naming the module and where to declare it' do
          is_expected.to compile.and_raise_error(%r{windowspowershell::script\[Get-Example\]: module 'Acme' is not declared.*windowspowershell::module \{ 'Acme'})
        end
      end

      # The version literal in script.pp has to equal the default of
      # windowspowershell::module, or a module left at its defaults and its
      # scripts would disagree on the path.
      context 'with a module left at its defaults' do
        it 'agrees with the module define on the default version folder' do
          is_expected.to contain_windowspowershell__module('Acme')
          is_expected.to contain_file(functions).with_ensure('directory')
          is_expected.to contain_file("#{functions}\\Get-Example.ps1").that_requires("File[#{functions}]")
        end
      end

      context 'with two scripts for two different in-house modules' do
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::module { 'Acme': }
            windowspowershell::module { 'OtherModule': }
            windowspowershell::script { 'Get-Other': modulename => 'OtherModule', content => 'x' }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it 'builds both modules independently' do
          is_expected.to contain_windowspowershell__module('Acme')
          is_expected.to contain_windowspowershell__module('OtherModule')
          is_expected.to contain_file("#{functions}\\Get-Example.ps1")
          is_expected.to contain_file('C:\Program Files\WindowsPowerShell\Modules\OtherModule\1.0\Functions\Get-Other.ps1')
        end
      end

      context 'with a folder' do
        let(:params) { super().merge('folder' => 'Windowsupdate') }

        it { is_expected.to compile.with_all_deps }

        it 'creates the folder and requires it' do
          is_expected.to contain_file("#{functions}\\Windowsupdate").with_ensure('directory')
          is_expected.to contain_file("#{functions}\\Windowsupdate\\Get-Example.ps1").
            that_requires("File[#{functions}\\Windowsupdate]")
        end
      end

      context 'with a source' do
        let(:params) { { 'modulename' => 'Acme', 'source' => 'puppet:///modules/profile/Get-Example.ps1' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file("#{functions}\\Get-Example.ps1").with_source('puppet:///modules/profile/Get-Example.ps1') }
      end

      context 'with a scriptname that differs from the title' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'Get-Other', 'content' => 'x' } }

        it { is_expected.to contain_file("#{functions}\\Get-Other.ps1") }
      end

      context 'with ensure => absent' do
        let(:params) { { 'modulename' => 'Acme', 'ensure' => 'absent', 'folder' => 'Windowsupdate' } }

        it { is_expected.to compile.with_all_deps }

        it 'removes the script and still rebuilds the manifest' do
          is_expected.to contain_file("#{functions}\\Windowsupdate\\Get-Example.ps1").
            with_ensure('absent').
            that_notifies('Exec[windowspowershell update-manifest Acme]')
        end

        it 'does not create the folder for a script it is removing' do
          is_expected.not_to contain_file("#{functions}\\Windowsupdate")
        end
      end

      # Issue #88: a present script targeting an absent module would rebuild a
      # tree the module just removed. Retire the script first instead.
      context 'with ensure => present targeting an absent module' do
        let(:pre_condition) { "windowspowershell::module { 'Acme': ensure => absent }" }

        it { is_expected.to compile.and_raise_error(%r{module 'Acme' is absent}) }
      end

      context 'with ensure => absent targeting an absent module' do
        let(:pre_condition) { "windowspowershell::module { 'Acme': ensure => absent }" }
        let(:params) { { 'modulename' => 'Acme', 'ensure' => 'absent' } }

        it { is_expected.to compile.with_all_deps }

        it 'removes the script without notifying the manifest refresh, which no longer exists' do
          is_expected.to contain_file("#{functions}\\Get-Example.ps1").with_ensure('absent')
          expect(catalogue.resource('File', "#{functions}\\Get-Example.ps1")[:notify]).to be_nil
          is_expected.not_to contain_exec('windowspowershell update-manifest Acme')
        end
      end

      context 'with no modulename' do
        let(:params) { { 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{expects a value for parameter 'modulename'}) }
      end

      context 'with a modulename holding an apostrophe' do
        let(:params) { { 'modulename' => "Evil'; calc.exe #", 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'modulename'}) }
      end

      context 'with neither content nor source' do
        let(:params) { { 'modulename' => 'Acme' } }

        it { is_expected.to compile.and_raise_error(%r{one of 'content' or 'source' is required}) }
      end

      context 'with an empty content string' do
        let(:params) { { 'modulename' => 'Acme', 'content' => '' } }

        # content is Optional[String[1]], matching source: an empty string must
        # not slip past the mutual-exclusion check and deploy a blank script.
        it { is_expected.to compile.and_raise_error(%r{parameter 'content'}) }
      end

      context 'with both content and source' do
        let(:params) { { 'modulename' => 'Acme', 'content' => 'x', 'source' => 'puppet:///modules/profile/x.ps1' } }

        it { is_expected.to compile.and_raise_error(%r{mutually exclusive}) }
      end

      context 'with a scriptname that tries to escape the module' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => '..\\..\\evil', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with a folder nested deeper than one level' do
        let(:params) { { 'modulename' => 'Acme', 'folder' => 'a\\b', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'folder'}) }
      end

      # '..' is a single path component, so the separator exclusion alone does
      # not catch it; it is refused for ending in a dot.
      context 'with a folder that is the parent directory' do
        let(:params) { { 'modulename' => 'Acme', 'folder' => '..', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'folder'}) }
      end

      context 'with a scriptname that is the parent directory' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => '..', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with a scriptname that is the current directory' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => '.', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      # The generated PowerShell quotes these values with apostrophes, so an
      # apostrophe in the name would close the string and run what follows.
      context 'with a scriptname holding an apostrophe' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => "Get-Evil'; calc.exe #", 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with a scriptname holding a typographic single quote' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => "Get-Evil\u2019; calc.exe #", 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with a folder holding an apostrophe' do
        let(:params) { { 'modulename' => 'Acme', 'folder' => "Evil'; calc.exe #", 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'folder'}) }
      end

      context 'with a scriptname ending in a space' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'Get-Example ', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      # Windows reserves CON, PRN, AUX, NUL, COM1-9 and LPT1-9 with or
      # without an extension; each would fail at apply time instead.
      context 'with the reserved scriptname CON' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'CON', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved scriptname con' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'con', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved scriptname NUL' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'NUL', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved scriptname PRN' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'PRN', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved scriptname AUX' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'AUX', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved scriptname COM1' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'COM1', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved scriptname COM9' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'COM9', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved scriptname LPT1' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'LPT1', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved scriptname LPT9' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'LPT9', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved scriptname CON.v2' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'CON.v2', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved scriptname COM1.txt' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'COM1.txt', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      # Windows strips spaces before the extension, so `CON .txt` still
      # names the CON device.
      context 'with the reserved scriptname holding a space before the dot' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'CON .txt', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with the reserved folder CON' do
        let(:params) { { 'modulename' => 'Acme', 'folder' => 'CON', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'folder'}) }
      end

      context 'with the reserved modulename NUL' do
        let(:params) { { 'modulename' => 'NUL', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'modulename'}) }
      end

      # Dots elsewhere are legitimate and must keep working.
      context 'with a scriptname holding an inner dot' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'Get-Example.v2', 'content' => 'x' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file("#{functions}\\Get-Example.v2.ps1") }
      end

      context 'with a scriptname ending in .ps1' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'Get-Foo.ps1', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with a scriptname ending in .psm1' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'Get-Foo.psm1', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      context 'with a scriptname ending in .PS1 (upper case)' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'Get-Foo.PS1', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      # Only whole components (with or without an extension) are reserved:
      # longer names starting with one must keep working.
      context 'with a scriptname starting with a reserved device name' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'CONSOLE', 'content' => 'x' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file("#{functions}\\CONSOLE.ps1") }
      end

      context 'with a scriptname extending a reserved device name with a dash' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'Console-Tools', 'content' => 'x' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file("#{functions}\\Console-Tools.ps1") }
      end

      context 'with a scriptname holding a longer device number' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'COM10', 'content' => 'x' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file("#{functions}\\COM10.ps1") }
      end

      context 'with a scriptname starting with a reserved device name plus an extension' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'CONSOLE.txt', 'content' => 'x' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file("#{functions}\\CONSOLE.txt.ps1") }
      end

      context 'with two scripts sharing a folder' do
        let(:params) { { 'modulename' => 'Acme', 'folder' => 'Windowsupdate', 'content' => 'x' } }
        let(:pre_condition) do
          <<~PUPPET
            windowspowershell::module { 'Acme': }
            windowspowershell::script { 'Get-Sibling':
              modulename => 'Acme',
              folder     => 'Windowsupdate',
              content    => 'y',
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }
      end
    end
  end

  context 'on a non-Windows node' do
    let(:facts) { { 'os' => { 'family' => 'RedHat', 'name' => 'RedHat' } } }
    let(:params) { { 'modulename' => 'Acme', 'folder' => 'Windowsupdate', 'content' => 'x' } }
    let(:pre_condition) { "windowspowershell::module { 'Acme': }" }

    it { is_expected.to compile.with_all_deps }

    it 'declares no file at all' do
      expect(catalogue.resources.select { |r| r.type == 'File' }).to be_empty
    end

    it 'still validates its parameters' do
      expect { catalogue }.not_to raise_error
    end

    context 'with a bad scriptname' do
      let(:params) { { 'modulename' => 'Acme', 'scriptname' => '..\\..\\evil', 'content' => 'x' } }

      it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
    end

    context 'with neither content nor source' do
      let(:params) { { 'modulename' => 'Acme' } }

      it { is_expected.to compile.and_raise_error(%r{one of 'content' or 'source' is required}) }
    end
  end
end
