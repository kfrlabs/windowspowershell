# @summary Creates the machine-wide PowerShell module directory shared by
#   every in-house module and by external module installs.
#
# @api private
class windowspowershell::install {
  assert_private()

  # module_root is a machine-wide, widely shared path
  # (C:\Program Files\WindowsPowerShell\Modules). ensure_resource lets another
  # module in the fleet manage the same directory without a duplicate
  # declaration, as long as both declare it identically. Every
  # windowspowershell::module and windowspowershell::external_module
  # instance requires File[$windowspowershell::normalized_module_root],
  # declared exactly once here.
  ensure_resource('file', $windowspowershell::normalized_module_root, {
      'ensure' => 'directory',
  })

  # Issue #96: the file provider does not create missing parents, so a custom
  # module_root whose parent does not exist used to fail the run with the
  # provider's generic message ('parent directory ... does not exist') while
  # every dependent resource was skipped in cascade (exit 4 with
  # --detailed-exitcodes). Whether the parent exists is node state,
  # unknowable at compile time, so this guard checks it at the start of the
  # run, ordered before File[$windowspowershell::normalized_module_root], and fails with a message naming
  # module_root and the missing parent instead.
  #
  # The parent is derived from the normalized root (issue #111 strips a
  # trailing separator in windowspowershell::normalized_module_root first),
  # with pure string operations so that a catalogue for
  # Windows still compiles on a Linux master (Ruby's File.dirname follows the
  # platform separator, so on Linux it answers '.' for a backslashed path).
  # The patterns are regex literals with every '/' written '\/': the lexer
  # ends a literal at a bare '/' even inside '[...]', and a String pattern
  # reaches Ruby's Regexp with its backslashes already collapsed once, which
  # breaks the same class. A bare drive ('C:' stripped from 'C:\Modules') is
  # re-anchored to its root
  # ('C:\'), which also names a missing drive explicitly. Degenerate roots
  # name no checkable parent and skip the guard: a bare drive root ('C:\' is
  # its own parent) and a bare UNC share root ('\\server\share', whose parent
  # '\\server' is not a directory Test-Path can check). A '\\?\' root skips
  # it too: the 5.1 provider behind Test-Path does not understand the
  # extended prefix, so the check would fail closed on an existing directory.
  #
  # Deliberately not auto-creation: silently growing an arbitrary tree as
  # SYSTEM would turn a typo in module_root into a green run deploying
  # modules where PowerShell never looks, and a full ancestor chain needs
  # fragile drive/UNC/extended-prefix surgery in the DSL for which Puppet
  # offers no primitive. A mkdir-style Exec would also add a PowerShell spawn
  # to every run (see 'Execution cost per run' in the README).
  $stripped_root = regsubst($windowspowershell::normalized_module_root, /[\/\\]+$/, '')
  $raw_parent = regsubst($stripped_root, /[\/\\][^\/\\]*$/, '')
  $full_parent = $raw_parent =~ /^[A-Za-z]:$/ ? {
    true    => "${raw_parent}\\",
    default => $raw_parent,
  }
  $no_checkable_parent = $full_parent == '' or $full_parent == $stripped_root or $full_parent == $windowspowershell::normalized_module_root
  $bare_server_parent = $full_parent =~ /^[\/\\][\/\\][^\/\\]+$/
  $extended_root = $windowspowershell::normalized_module_root =~ /^[\/\\][\/\\]\?/
  $skip_guard = $no_checkable_parent or $bare_server_parent or $extended_root
  $parent_check = $skip_guard ? {
    true    => undef,
    default => $full_parent,
  }

  if $parent_check =~ NotUndef {
    exec { 'windowspowershell module_root parent exists':
      command   => "throw 'windowspowershell: module_root ''${windowspowershell::module_root}'' (normalized ''${windowspowershell::normalized_module_root}'') was not created: parent directory ''${parent_check}'' does not exist. Create it on the node, or fix the typo in module_root: the file resource does not create missing parents.'",
      unless    => "if (-not (Test-Path -LiteralPath '${parent_check}')) { exit 1 }",
      provider  => powershell,
      logoutput => on_failure,
      before    => File[$windowspowershell::normalized_module_root],
    }
  }
}
