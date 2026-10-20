require 'spec_helper'

describe 'Windowspowershell::Version' do
  # Deliberately looser than Moduleversion: external_module accepts a single
  # component (`2`) and short pins (`2.1`), which PowerShellGet and the
  # numeric version comparison normalise.
  it { is_expected.to allow_values('2', '2.1', '2.1.0', '2.2.1.5') }
  it { is_expected.not_to allow_value('2.1.0.0.0') }
  it { is_expected.not_to allow_value("2.1'; calc.exe #") }

  # \z, not \Z: Puppet's Pattern matches partially, so a trailing newline must
  # not slip through.
  it { is_expected.not_to allow_value("2.1\n") }

  # Each component is parsed as an Int32 by System.Version, so ten digits
  # would overflow at Exec runtime.
  it { is_expected.not_to allow_value('9999999999.0') }
  it { is_expected.not_to allow_value('2.9999999999') }
end
