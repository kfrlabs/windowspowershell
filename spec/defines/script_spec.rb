require 'spec_helper'

describe 'windowspowershell::script' do
  let(:title) { 'Get-Example' }
  let(:params) { { 'modulename' => 'Acme', 'content' => "Write-Output 'example'\n" } }

  functions = 'C:\Program Files\WindowsPowerShell\Modules\Acme\1.0\Functions'

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'with content and no folder' do
        it { is_expected.to compile.with_all_deps }

        it 'implicitly builds the named in-house module with every default' do
          is_expected.to contain_windowspowershell__inhouse_module('Acme')
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
            windowspowershell::inhouse_module { 'Acme':
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

      context 'with two scripts for two different in-house modules' do
        let(:pre_condition) do
          "windowspowershell::script { 'Get-Other': modulename => 'OtherModule', content => 'x' }"
        end

        it { is_expected.to compile.with_all_deps }

        it 'builds both modules independently' do
          is_expected.to contain_windowspowershell__inhouse_module('Acme')
          is_expected.to contain_windowspowershell__inhouse_module('OtherModule')
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

      context 'with a folder holding an apostrophe' do
        let(:params) { { 'modulename' => 'Acme', 'folder' => "Evil'; calc.exe #", 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'folder'}) }
      end

      context 'with a scriptname ending in a space' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'Get-Example ', 'content' => 'x' } }

        it { is_expected.to compile.and_raise_error(%r{parameter 'scriptname'}) }
      end

      # Dots elsewhere are legitimate and must keep working.
      context 'with a scriptname holding an inner dot' do
        let(:params) { { 'modulename' => 'Acme', 'scriptname' => 'Get-Example.v2', 'content' => 'x' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file("#{functions}\\Get-Example.v2.ps1") }
      end

      context 'with two scripts sharing a folder' do
        let(:params) { { 'modulename' => 'Acme', 'folder' => 'Windowsupdate', 'content' => 'x' } }
        let(:pre_condition) do
          <<~PUPPET
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
