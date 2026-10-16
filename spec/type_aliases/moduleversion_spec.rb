require 'spec_helper'

describe 'Windowspowershell::Moduleversion' do
  it { is_expected.to allow_values('1.0', '2.3', '1.0.0', '1.0.0.0') }
  it { is_expected.not_to allow_value('1') }
  it { is_expected.not_to allow_value('1.0.0.0.0') }
  it { is_expected.not_to allow_value("1.0'; calc.exe #") }

  # \z, not \Z: Puppet's Pattern matches partially, so a trailing newline must
  # not slip through.
  it { is_expected.not_to allow_value("1.0\n") }

  # Each component is parsed as an Int32 by System.Version, so ten digits
  # would overflow at Exec runtime.
  it { is_expected.not_to allow_value('9999999999.0') }

  # Leading zeros are accepted, which is a known limitation rather than an
  # oversight: PowerShell reports the parsed version, the folder keeps the
  # literal name.
  it { is_expected.to allow_value('01.02') }
end
