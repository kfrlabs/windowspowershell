require 'spec_helper'
require 'facter'
require 'fileutils'
require 'tmpdir'

describe 'long_paths_enabled fact' do
  let(:fact_file) { File.expand_path('../../../lib/facter/long_paths_enabled.rb', __dir__) }

  # The fact requires win32/registry at resolution time, which does not exist
  # on the Linux CI host: shadow it with an empty file on the load path so
  # the require succeeds, then stub the registry hierarchy below.
  let(:fake_lib) { Dir.mktmpdir }

  before do
    Facter.clear
    allow(Facter.fact(:kernel)).to receive(:value).and_return('windows')
    FileUtils.mkdir_p(File.join(fake_lib, 'win32'))
    File.write(File.join(fake_lib, 'win32', 'registry.rb'), "# Fake win32 registry for fact specs.\n")
    $LOAD_PATH.unshift(fake_lib)
    load fact_file

    registry = Module.new
    stub_const('Win32::Registry', registry)
    registry.const_set(:REG_DWORD, 4)
    registry.const_set(:Error, Class.new(StandardError))
    # A bare Class.new only carries the private Kernel#open, and a stub of a
    # private method stays private, so an explicit .open receiver would raise
    # NoMethodError (a StandardError the fact rescues into false). A real
    # public .open keeps the per-test stubs below reachable.
    hklm = Class.new do
      def self.open(*_args)
        raise 'unstubbed Win32 registry call'
      end
    end
    registry.const_set(:HKEY_LOCAL_MACHINE, hklm)
  end

  after do
    $LOAD_PATH.delete(fake_lib)
    FileUtils.remove_entry(fake_lib)
    Facter.clear
  end

  # Minimal stand-in for an open registry key: the fact only calls #[] on it.
  def stub_long_paths_enabled(value)
    reg = Struct.new(:value) do
      def [](_name, _type)
        value
      end
    end.new(value)
    allow(Win32::Registry::HKEY_LOCAL_MACHINE).to receive(:open).
      with('SYSTEM\\CurrentControlSet\\Control\\FileSystem').and_yield(reg)
  end

  context 'with LongPathsEnabled set to 1' do
    before { stub_long_paths_enabled(1) }

    it 'reports long paths enabled' do
      expect(Facter.fact(:long_paths_enabled).value).to be(true)
    end
  end

  context 'with LongPathsEnabled set to 0' do
    before { stub_long_paths_enabled(0) }

    it 'reports long paths disabled' do
      expect(Facter.fact(:long_paths_enabled).value).to be(false)
    end
  end

  context 'with the registry key missing' do
    before do
      allow(Win32::Registry::HKEY_LOCAL_MACHINE).to receive(:open).
        with('SYSTEM\\CurrentControlSet\\Control\\FileSystem').
        and_raise(Win32::Registry::Error, 'The system cannot find the file specified.')
    end

    it 'reports long paths disabled rather than failing' do
      expect(Facter.fact(:long_paths_enabled).value).to be(false)
    end
  end

  context 'when reading the registry raises' do
    before do
      allow(Win32::Registry::HKEY_LOCAL_MACHINE).to receive(:open).
        with('SYSTEM\\CurrentControlSet\\Control\\FileSystem').
        and_raise(StandardError, 'access denied')
    end

    it 'reports long paths disabled rather than failing' do
      expect(Facter.fact(:long_paths_enabled).value).to be(false)
    end
  end

  context 'on a node that is not Windows' do
    before { allow(Facter.fact(:kernel)).to receive(:value).and_return('Linux') }

    it 'does not resolve at all' do
      expect(Facter.fact(:long_paths_enabled).value).to be_nil
    end
  end
end
