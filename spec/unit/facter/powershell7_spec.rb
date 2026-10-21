require 'spec_helper'
require 'facter'
require 'fileutils'
require 'tmpdir'

describe 'powershell7 fact' do
  let(:fact_file) { File.expand_path('../../../lib/facter/powershell7.rb', __dir__) }
  let(:default_path) { File.join('C:\\Program Files', 'PowerShell', '7', 'pwsh.exe') }

  before do
    Facter.clear
    allow(Facter.fact(:kernel)).to receive(:value).and_return('windows')
    stub_const('ENV', ENV.to_hash.merge('ProgramFiles' => 'C:\\Program Files'))
    load fact_file
  end

  after { Facter.clear }

  context 'with pwsh.exe at its default location' do
    before { allow(File).to receive(:exist?).with(default_path).and_return(true) }

    it 'reports it installed, with its path' do
      expect(Facter.fact(:powershell7).value).to eq('installed' => true, 'path' => default_path)
    end
  end

  # The module only manages the profile next to the default install, so a pwsh
  # anywhere else (ZIP, Microsoft Store, 32-bit) is reported as not installed.
  context 'with pwsh.exe only somewhere else' do
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(default_path).and_return(false)
    end

    it 'reports it not installed' do
      expect(Facter.fact(:powershell7).value).to eq('installed' => false, 'path' => default_path)
    end
  end

  context 'without %ProgramFiles% in the environment' do
    before do
      stub_const('ENV', ENV.to_hash.reject { |key, _| key == 'ProgramFiles' })
      allow(File).to receive(:exist?).with(default_path).and_return(true)
    end

    it 'falls back to C:\\Program Files' do
      expect(Facter.fact(:powershell7).value).to eq('installed' => true, 'path' => default_path)
    end
  end

  context 'on a node that is not Windows' do
    before { allow(Facter.fact(:kernel)).to receive(:value).and_return('Linux') }

    it 'does not resolve at all' do
      expect(Facter.fact(:powershell7).value).to be_nil
    end
  end

  # No File stub here: the real File.join / File.exist? run against a real tree.
  context 'against a real directory tree' do
    let(:program_files) { Dir.mktmpdir }
    let(:pwsh7) { File.join(program_files, 'PowerShell', '7', 'pwsh.exe') }

    before { stub_const('ENV', ENV.to_hash.merge('ProgramFiles' => program_files)) }

    after { FileUtils.remove_entry(program_files) }

    it 'finds pwsh.exe where the MSI puts it' do
      FileUtils.mkdir_p(File.dirname(pwsh7))
      FileUtils.touch(pwsh7)
      expect(Facter.fact(:powershell7).value).to eq('installed' => true, 'path' => pwsh7)
    end

    it 'does not mistake another PowerShell major version for 7' do
      FileUtils.mkdir_p(File.join(program_files, 'PowerShell', '6'))
      FileUtils.touch(File.join(program_files, 'PowerShell', '6', 'pwsh.exe'))
      expect(Facter.fact(:powershell7).value).to eq('installed' => false, 'path' => pwsh7)
    end
  end
end
