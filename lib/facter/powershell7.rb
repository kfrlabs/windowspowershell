# @summary Reports whether PowerShell 7 (pwsh.exe) is installed machine-wide.
#
# Detection is by the presence of pwsh.exe on disk rather than the package
# inventory (the `packages_version` fact), which only sees the x64 MSI install
# and misses ZIP, Microsoft Store, winget and 32-bit installations. What the
# module actually needs to know is whether there is a PowerShell 7 whose
# machine-wide profile it can manage, and the file on disk is exactly that.
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
