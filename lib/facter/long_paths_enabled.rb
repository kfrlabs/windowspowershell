# @summary Reports whether Windows long-path support is enabled.
#
# Reads `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled`
# (Windows 10 1607 and later). `true` means the node opts out of the
# historical 260-character `MAX_PATH` limit, so the module's compile-time
# path-length checks stay silent there; `false` (or any read failure) keeps
# the `path_length_policy` behavior. The fact is confined to Windows and is
# absent (`nil`) on any other kernel.
Facter.add('long_paths_enabled') do
  confine kernel: 'windows'

  setcode do
    require 'win32/registry'
    Win32::Registry::HKEY_LOCAL_MACHINE.open('SYSTEM\\CurrentControlSet\\Control\\FileSystem') do |reg|
      reg['LongPathsEnabled', Win32::Registry::REG_DWORD] == 1
    end
  rescue StandardError
    false
  end
end
