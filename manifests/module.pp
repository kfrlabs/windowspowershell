# @summary Installs a third-party PowerShell module, either from a repository
#   such as the PowerShell Gallery or by copying files from a Puppet source.
#
# One resource manages one module, not one version, so `ensure` carries the
# version the way it does on the `package` type. By default every other version
# found side by side is removed, which is what makes a single resource enough
# to express "this node runs 2.2.1.5 and nothing else".
#
# This is separate from `windowspowershell::script`: a third-party module ships
# its own manifest, so it takes no part in regenerating the in-house one.
#
# @param ensure
#   `absent` removes every version installed under the machine-wide (`AllUsers`)
#   module directory and unregisters the module from PowerShellGet. `present`
#   accepts any version and installs the newest one if none is there, which
#   requires `repository`. It is install-once: once any version is present it is
#   never upgraded on later runs. To move a node to a newer version, pin that
#   version in `ensure`.
#   A version string pins that exact version.
# @param modulename
#   Name of the PowerShell module. Defaults to the resource title.
# @param repository
#   Repository to install from, e.g. `PSGallery`. Mutually exclusive with
#   `source`.
# @param source
#   Puppet file source holding the module files, for nodes that cannot reach a
#   repository. Mutually exclusive with `repository`.
# @param purge_versions
#   Whether to remove versions of the module other than the one in `ensure`.
#   Ignored unless `ensure` is a version.
# @param import_in_profile
#   Whether to add an `Import-Module` line for this module to every profile
#   file managed by `windowspowershell::config` (see `manage_profiles` /
#   `manage_pwsh_profile` on the main class). Pins `-RequiredVersion` when
#   `ensure` is a specific version. Ignored (no-op) when `ensure => absent`.
#
# @example Pin a version from the PowerShell Gallery
#   windowspowershell::module { 'PSWindowsUpdate':
#     ensure     => '2.2.1.5',
#     repository => 'PSGallery',
#   }
#
# @example Copy the files from a Puppet source instead
#   windowspowershell::module { 'PSWindowsUpdate':
#     ensure => '2.2.1.5',
#     source => 'puppet:///modules/windowsupdate/PSWindowsUpdate/2.2.1.5/',
#   }
#
# @example Remove a module entirely
#   windowspowershell::module { 'PSWindowsUpdate':
#     ensure => absent,
#   }
define windowspowershell::module (
  Windowspowershell::Moduleensure $ensure = 'present',
  Windowspowershell::Name $modulename = $name,
  Optional[Windowspowershell::Reponame] $repository = undef,
  Optional[String[1]] $source = undef,
  Boolean $purge_versions = true,
  Boolean $import_in_profile = false,
) {
  include windowspowershell

  # Validated on every node, including the ones where this is a no-op, so a
  # mistake is caught by the first agent to compile it.
  if $repository =~ NotUndef and $source =~ NotUndef {
    fail("windowspowershell::module[${name}]: 'repository' and 'source' are mutually exclusive.")
  }
  if $ensure == 'present' and $source =~ NotUndef {
    fail("windowspowershell::module[${name}]: 'source' needs an explicit version in 'ensure', because it has to know which version directory to populate.")
  }
  if $ensure == 'present' and $repository =~ Undef {
    fail("windowspowershell::module[${name}]: ensure => present needs a 'repository' to install from. Pin a version and pass a 'source' to deploy files instead.")
  }

  $module_dir     = "${windowspowershell::module_root}\\${modulename}"
  $module_version = $ensure ? {
    'present' => undef,
    'absent'  => undef,
    default   => $ensure,
  }

  if !$windowspowershell::supported {
    # No-op: see windowspowershell::supported.
  } elsif $ensure == 'absent' {
    # One resource is one module, so absent takes the whole tree, every version
    # included. Uninstall-Module clears the PowerShellGet record first, so
    # Get-InstalledModule stops listing the module; the directory purge that
    # follows then catches versions deployed by file copy, which PowerShellGet
    # never knew about.
    #
    # The Exec title is keyed on $name, not $modulename: two resources may share
    # a modulename under different titles, and keying on modulename would clash
    # them on an Exec neither user wrote.
    exec { "windowspowershell uninstall ${name}":
      command   => epp('windowspowershell/uninstall_psmodule.ps1.epp', {
          'modulename' => $modulename,
          'module_dir' => $module_dir,
      }),
      unless    => epp('windowspowershell/check_psmodule_absent.ps1.epp', {
          'modulename' => $modulename,
          'module_dir' => $module_dir,
      }),
      provider  => powershell,
      timeout   => 300,
      logoutput => on_failure,
    }
  } else {
    if $repository =~ NotUndef {
      include windowspowershell::psget

      exec { "windowspowershell install ${name}":
        command   => epp('windowspowershell/install_psmodule.ps1.epp', {
            'modulename' => $modulename,
            'version'    => $module_version,
            'repository' => $repository,
            'proxy'      => $windowspowershell::proxy_url,
        }),
        unless    => epp('windowspowershell/check_psmodule.ps1.epp', {
            'module_dir' => $module_dir,
            'version'    => $module_version,
        }),
        provider  => powershell,
        timeout   => 900,
        logoutput => on_failure,
        require   => Exec['windowspowershell install nuget provider'],
      }
      $installed_by = Exec["windowspowershell install ${name}"]
    } else {
      # Shared by every version of the same module, hence ensure_resource.
      ensure_resource('file', $module_dir, {
          'ensure'  => 'directory',
          'require' => File[$windowspowershell::module_root],
      })

      file { "${module_dir}\\${module_version}":
        ensure  => directory,
        recurse => true,
        source  => pick($source, "puppet:///modules/windowspowershell/modules/${modulename}/${module_version}/"),
        require => File[$module_dir],
      }
      $installed_by = File["${module_dir}\\${module_version}"]
    }

    # Purging by directory rather than Uninstall-Module on purpose: it also
    # catches versions this module deployed by file copy, which PowerShellGet
    # has no record of.
    if $purge_versions and $module_version =~ NotUndef {
      exec { "windowspowershell purge other versions of ${name}":
        command   => epp('windowspowershell/purge_psmodule_versions.ps1.epp', {
            'module_dir' => $module_dir,
            'version'    => $module_version,
        }),
        unless    => epp('windowspowershell/check_psmodule_versions.ps1.epp', {
            'module_dir' => $module_dir,
            'version'    => $module_version,
        }),
        provider  => powershell,
        timeout   => 300,
        logoutput => on_failure,
        require   => $installed_by,
      }
    }

    if $import_in_profile {
      $import_content = epp('windowspowershell/import_module.ps1.epp', {
          'modulename' => $modulename,
          'version'    => $module_version,
      })

      # Same collector pattern as windowspowershell::inhouse_module: the
      # Import-Module line lands on the profile File resources themselves.
      $windowspowershell::profile_paths.each |$profile_path| {
        File <| title == $profile_path |> {
          content => $import_content,
        }
      }
    }
  }
}
