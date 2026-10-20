require 'spec_helper'
require 'facter'

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
end
