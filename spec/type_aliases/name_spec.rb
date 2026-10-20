require 'spec_helper'

describe 'Windowspowershell::Name' do
  it { is_expected.to allow_values('Get-Example', 'Get-Example.v2', 'Windowsupdate', 'COM10', 'Console-Tools') }

  it { is_expected.not_to allow_value("Evil'; calc.exe #") }
  it { is_expected.not_to allow_value('..') }
  it { is_expected.not_to allow_value('a\\b') }

  # PowerShell treats U+2018 to U+201B as single-quote characters, so each of
  # them can end a single-quoted string exactly like an apostrophe.
  ["\u2018", "\u2019", "\u201A", "\u201B"].each do |quote|
    it { is_expected.not_to allow_value("Get-Evil#{quote}; calc.exe #") }
    it { is_expected.not_to allow_value("#{quote}Evil") }
  end

  # Other non-ASCII text is not special inside a single-quoted string.
  it { is_expected.to allow_value("Caf\u00E9-Tools") }
end
