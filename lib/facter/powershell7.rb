# @summary Reports whether PowerShell 7 (pwsh.exe) is installed at its default
#   machine-wide location.
#
# Detection is by the presence of pwsh.exe at `%ProgramFiles%\PowerShell\7`
# only, which is where the MSI package installs it. That is deliberate: the
# module manages the machine-wide profile at that same location
# (`C:\Program Files\PowerShell\7\profile.ps1`), and PowerShell only loads a
# machine-wide profile from its own install directory. A ZIP install
# elsewhere, a Microsoft Store install (read-only `WindowsApps`) or a 32-bit
# install would not load that profile, so reporting them as installed would
# make the module manage a profile no pwsh ever reads. They are reported as
# not installed.
#
# Structured value:
#   { 'installed' => Boolean, 'path' => String }
Facter.add('powershell7') do
  confine kernel: 'windows'

  setcode do
    program_files = ENV['ProgramFiles'] || 'C:\\Program Files'
    pwsh_path = File.join(program_files, 'PowerShell', '7', 'pwsh.exe')

    {
      'installed' => File.exist?(pwsh_path),
      'path'      => pwsh_path,
    }
  end
end
