require 'spec_helper'

describe 'Windowspowershell::Rootpath' do
  it { is_expected.to allow_values('C:\\Program Files\\WindowsPowerShell\\Modules', '\\\\server\\share\\Modules', '\\\\?\\C:\\Modules') }

  it { is_expected.not_to allow_value('Modules') }
  it { is_expected.not_to allow_value("C:\\x'; calc.exe #") }

  # PowerShell treats U+2018 to U+201B as single-quote characters, so each of
  # them can end a single-quoted string exactly like an apostrophe, whichever
  # segment of the path holds it.
  ["\u2018", "\u2019", "\u201A", "\u201B"].each do |quote|
    it { is_expected.not_to allow_value("C:\\x#{quote}; calc.exe #") }
    it { is_expected.not_to allow_value("\\\\ser#{quote}ver\\share") }
    it { is_expected.not_to allow_value("\\\\server\\sha#{quote}re") }
    it { is_expected.not_to allow_value("\\\\?\\C:#{quote}x") }
  end
end
