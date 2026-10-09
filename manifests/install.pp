# @summary Creates the machine-wide PowerShell module directory shared by
#   every in-house module and by third-party module installs.
#
# @api private
class windowspowershell::install {
  assert_private()

  # module_root is a machine-wide, widely shared path
  # (C:\Program Files\WindowsPowerShell\Modules). ensure_resource lets another
  # module in the fleet manage the same directory without a duplicate
  # declaration, as long as both declare it identically. Every
  # windowspowershell::inhouse_module and windowspowershell::module
  # (third-party) instance requires File[$windowspowershell::module_root],
  # declared exactly once here.
  ensure_resource('file', $windowspowershell::module_root, {
    'ensure' => 'directory',
  })
}
