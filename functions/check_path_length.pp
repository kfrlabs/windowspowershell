# @summary Applies the path-length policy to an over-limit managed path.
#
# Called by `windowspowershell::module` and `windowspowershell::script` when
# a managed path exceeds the 259-character Windows `MAX_PATH` limit. On a
# node with long-path support (the `long_paths_enabled` fact is `true`) the
# message is dropped: the path is legitimate there. Otherwise the
# `windowspowershell::path_length_policy` class parameter decides: `fail`
# fails compilation with the message, `ignore` drops it, and `warn` (the
# default) logs it as a compile-time warning.
function windowspowershell::check_path_length(String[1] $message) {
  # A bare early `return` followed by a `case` does not compile: Puppet
  # rejects the leading `if` as a statement whose value is forgotten, so
  # the guard and the policy dispatch are one if/else expression instead.
  if $facts['long_paths_enabled'] == true {
    undef
  } else {
    case $windowspowershell::path_length_policy {
      'fail': {
        fail($message)
      }
      'ignore': {
        undef
      }
      default: {
        warning($message)
      }
    }
  }
}
