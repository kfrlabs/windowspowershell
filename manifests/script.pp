# @summary Deploys a PowerShell script as a function of an in-house module.
#
# The script is written under the target module's `Functions` directory and
# notifies that module's shared manifest-regeneration Exec, so it is exported
# on the next PowerShell session. Removing it is the same resource with
# `ensure => absent`.
#
# @param modulename
#   Name of the in-house module (a `windowspowershell::inhouse_module`
#   resource) this script is deployed into. Mandatory: there is no default
#   module any more, so every script has to say where it is going. A module
#   named here that was never declared explicitly is created with every
#   default (see `windowspowershell::inhouse_module`).
# @param ensure
#   Whether the script should be present or absent.
# @param scriptname
#   Base name of the script, without the `.ps1` extension. Defaults to the
#   resource title. This is also the name of the exported PowerShell function.
# @param folder
#   Optional sub-folder under `Functions`, to group scripts by domain.
# @param content
#   Literal content of the script. Mutually exclusive with `source`.
# @param source
#   Puppet file source for the script. Mutually exclusive with `content`.
#
# @example
#   windowspowershell::script { 'Get-WUParams':
#     modulename => 'Acme',
#     folder     => 'Windowsupdate',
#     content    => template('windowsupdate/windowspowershell/Get-WUParams.ps1.erb'),
#   }
#
# @example Retire a script that is no longer shipped
#   windowspowershell::script { 'Get-OldThing':
#     modulename => 'Acme',
#     ensure     => absent,
#   }
define windowspowershell::script (
  Windowspowershell::Name $modulename,
  Enum['present', 'absent'] $ensure = 'present',
  Windowspowershell::Name $scriptname = $name,
  Optional[Windowspowershell::Name] $folder = undef,
  Optional[String[1]] $content = undef,
  Optional[String[1]] $source = undef,
) {
  include windowspowershell

  # Validation runs on every node, including the ones where the resource is a
  # no-op, so a typo is caught by the first Linux agent to compile it rather
  # than only once it reaches a Windows one.
  if $content =~ NotUndef and $source =~ NotUndef {
    fail("windowspowershell::script[${name}]: 'content' and 'source' are mutually exclusive.")
  }
  if $ensure == 'present' and $content =~ Undef and $source =~ Undef {
    fail("windowspowershell::script[${name}]: one of 'content' or 'source' is required when ensure => present.")
  }

  # The target module gets every default when nothing declared it yet, the
  # same way windowspowershell::module shares a module directory it did not
  # create. getparam then reads back the version this particular module
  # identity resolved to -- either the default above, or whatever an explicit
  # windowspowershell::inhouse_module { $modulename: ... } declared earlier --
  # since this define does not own that resource and must not guess its path
  # independently.
  ensure_resource('windowspowershell::inhouse_module', $modulename)
  $module_version = getparam(Windowspowershell::Inhouse_module[$modulename], 'version')
  $functions_path = "${windowspowershell::module_root}\\${modulename}\\${module_version}\\Functions"

  $script_folder = $folder ? {
    undef   => $functions_path,
    default => "${functions_path}\\${folder}",
  }
  $script_path = "${script_folder}\\${scriptname}.ps1"

  if !$windowspowershell::supported {
    # No-op: the class declares nothing on this node, so there is no Functions
    # directory to write into and no Exec to notify.
  } elsif $ensure == 'present' {
    # The Functions directory itself belongs to windowspowershell::inhouse_module;
    # only a sub-folder needs creating here, and it is shared by every script
    # that names it, hence ensure_resource.
    if $folder =~ NotUndef {
      ensure_resource('file', $script_folder, {
        'ensure'  => 'directory',
        'require' => File[$functions_path],
      })
    }

    file { $script_path:
      ensure  => file,
      content => $content,
      source  => $source,
      require => File[$script_folder],
      notify  => [
        Exec["windowspowershell update-manifest ${modulename}"],
        Exec["windowspowershell unblock-files ${modulename}"],
      ],
    }
  } else {
    file { $script_path:
      ensure => absent,
      notify => Exec["windowspowershell update-manifest ${modulename}"],
    }
  }
}
