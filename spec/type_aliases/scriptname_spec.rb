require 'spec_helper'

describe 'Windowspowershell::Scriptname' do
  it { is_expected.to allow_values('Get-Example', 'Get-Example.v2', 'Get-Foo.ps1.bak', 'COM10', 'Console-Tools') }

  it { is_expected.not_to allow_value('Get-Foo.ps1') }
  it { is_expected.not_to allow_value('Get-Foo.psm1') }
  it { is_expected.not_to allow_value('Get-Foo.PS1') }
  it { is_expected.not_to allow_value('Get-Foo.PSM1') }
  it { is_expected.not_to allow_value("Evil'; calc.exe #") }
  it { is_expected.not_to allow_value('..') }

  ["\u2018", "\u2019", "\u201A", "\u201B"].each do |quote|
    it { is_expected.not_to allow_value("Get-Evil#{quote}; calc.exe #") }
  end
end
