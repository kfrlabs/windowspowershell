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
#   A version string pins that exact version. PowerShellGet may normalise a
#   short pin into a longer folder name (e.g. pin `2.1` installs under
#   `2.1.0`); that normalised folder counts as the pinned version, so the
#   install check stays idempotent and the purge keeps it.
#   An interrupted install may leave an empty or partial version folder behind:
#   a folder only counts as installed when `<modulename>.psd1` exists inside it
#   and passes `Test-ModuleManifest`, so the next run reinstalls and repairs it
#   instead of treating it as installed forever (issue #106). Names holding
#   wildcard characters (`` ` ``, `*`, `?`, `[`, `]`) are excluded from the
#   manifest parse -- `Test-ModuleManifest` rejects wildcards in
#   `RootModule`/`ModuleToProcess`, which would reinstall a healthy wildcard
#   module on every run -- so for those names the `.psd1` only has to exist.
#   `absent` is refused for the protected system modules `PowerShellGet` and
#   `PackageManagement` (issue #88): removing them breaks Install-Module for
#   every later run.
# @param modulename
#   Name of the PowerShell module. Defaults to the resource title.
#   `Install-Module`, `Get-InstalledModule`, `Uninstall-Module` and
#   `Import-Module` interpret `-Name` as a wildcard: `*`, `?`, `[` `]` and
#   the backtick itself are escaped with a backtick in the generated scripts,
#   so a literal name is always targeted (in-house names such as `Acme[Beta]`
#   keep working, e.g. via the file-copy backend).
#   Declare one resource per `modulename`: two resources sharing a
#   `modulename` under different titles each purge the other side's version
#   (see `purge_versions`), so the node flaps between both versions and never
#   converges. Sharing is only supported with `purge_versions => false` on all
#   but one side, and only with the `repository` backend: with the `source`
#   backend both titles declare the same versioned `File` directory, which
#   fails the catalogue with a duplicate resource.
# @param repository
#   Repository to install from, e.g. `PSGallery`. Mutually exclusive with
#   `source`. The install runs with `-Force -AllowClobber` as `SYSTEM`, which
#   suppresses the untrusted-repository prompt: the repository named here is
#   trusted to execute code as `SYSTEM`, so prefer an internal mirror in
#   production.
#   Requires the default `module_root`
#   (`C:\Program Files\WindowsPowerShell\Modules`):
#   `Install-Module -Scope AllUsers` always installs there and ignores a
#   custom root (issue #85), so a custom root would reinstall on every run.
#   The custom repository itself must be registered for the `SYSTEM` account
#   (`Register-PSRepository` is per-user): a repository registered in an
#   interactive session is invisible to the agent (see README).
# @param source
#   Puppet file source holding the module files, for nodes that cannot reach a
#   repository. Mutually exclusive with `repository`.
# @param purge_versions
#   Whether to remove versions of the module other than the one in `ensure`.
#   Ignored unless `ensure` is a version. Co-managing one modulename from both
#   `windowspowershell::external_module` and `windowspowershell::module`
#   requires `purge_versions => false` on one side, or each purge removes the
#   other side's version. The same holds for two `external_module` resources
#   sharing a `modulename`: keep a single resource per module, or set
#   `purge_versions => false` on all but one side when the sharing is
#   deliberate.
#   Comparison is numeric with missing segments treated as zero, so pin `2.1`
#   also matches folder `2.1.0`: if both spellings end up side by side, both
#   count as the pinned version and neither is purged. The canonical folder
#   is whatever the backend creates -- the normalised name PowerShellGet
#   picks for `repository`, the literal pin for `source` -- so remove the
#   other spelling once by hand if it ever appears.
# @param import_in_profile
#   Whether to add an `Import-Module` line for this module to every profile
#   file managed by `windowspowershell::config` (see `manage_profiles` /
#   `manage_pwsh_profile` on the main class). Pins `-RequiredVersion` when
#   `ensure` is a specific version. Ignored (no-op) when `ensure => absent`.
#   A single-component pin such as `2` is normalised to `2.0` for the
#   `-RequiredVersion` line, because `Import-Module -RequiredVersion` is
#   typed `[version]` and needs at least major.minor.
#
# @example Pin a version from the PowerShell Gallery
#   windowspowershell::external_module { 'PSWindowsUpdate':
#     ensure     => '2.2.1.5',
#     repository => 'PSGallery',
#   }
#
# @example Copy the files from a Puppet source instead
#   windowspowershell::external_module { 'PSWindowsUpdate':
#     ensure => '2.2.1.5',
#     source => 'puppet:///modules/windowsupdate/PSWindowsUpdate/2.2.1.5/',
#   }
#
# @example Remove a module entirely
#   windowspowershell::external_module { 'PSWindowsUpdate':
#     ensure => absent,
#   }
define windowspowershell::external_module (
  Windowspowershell::Externalmoduleensure $ensure = 'present',
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
    fail("windowspowershell::external_module[${name}]: 'repository' and 'source' are mutually exclusive.")
  }
  if $ensure == 'present' and $source =~ NotUndef {
    fail("windowspowershell::external_module[${name}]: 'source' needs an explicit version in 'ensure', because it has to know which version directory to populate.")
  }
  if $ensure == 'present' and $repository =~ Undef {
    fail("windowspowershell::external_module[${name}]: ensure => present needs a 'repository' to install from. Pin a version and pass a 'source' to deploy files instead.")
  }
  if $ensure != 'present' and $ensure != 'absent' and $repository =~ Undef and $source =~ Undef {
    fail("windowspowershell::external_module[${name}]: ensure => '${ensure}' needs a 'repository' or a 'source' to install from. Pin a version with 'repository' to install from a repository, or pass a 'source' holding the module files.")
  }
  # Protected system modules must survive (issue #88): removing PowerShellGet
  # or PackageManagement breaks Install-Module for every later run. Only
  # `absent` is refused -- installing or upgrading them stays legitimate.
  # Case-insensitive: PowerShell resolves module names without regard to case.
  if $ensure == 'absent' and $modulename.downcase in ['powershellget', 'packagemanagement'] {
    fail("windowspowershell::external_module[${name}]: refusing to remove protected system module '${modulename}' with ensure => absent: it breaks Install-Module for every later run. Remove the resource instead of declaring it absent.")
  }

  $module_dir     = "${windowspowershell::normalized_module_root}\\${modulename}"
  $module_version = $ensure ? {
    'present' => undef,
    'absent'  => undef,
    default   => $ensure,
  }

  # The repository backend installs with `Install-Module -Scope AllUsers`,
  # which always targets `C:\Program Files\WindowsPowerShell\Modules` and
  # ignores a custom `module_root` (verified on Windows Server 2025, issue
  # #85): the install check would then look in the custom directory, never
  # see the module, and reinstall on every run. Refuse that combination at
  # compile time instead of converging never. The `source` backend honours
  # `module_root` and stays available for isolated roots (integration test,
  # smoke test).
  if $repository =~ NotUndef {
    # Compared on normalized forms (issue #111): slash-normalized,
    # downcased and trailing-stripped, so a trailing separator on the
    # default root neither bypasses nor falsely triggers the #85 guard.
    $normalized_root = regsubst(regsubst(downcase($windowspowershell::normalized_module_root), '/', '\\', 'G'), /\\+$/, '')
    if $normalized_root != 'c:\\program files\\windowspowershell\\modules' {
      fail("windowspowershell::external_module[${name}]: 'repository' needs the default 'module_root' ('C:\\Program Files\\WindowsPowerShell\\Modules'): 'Install-Module -Scope AllUsers' always installs there and ignores a custom root, so the install check would miss the module and reinstall on every run. Keep the default root for repository-backed modules, or use 'source' for a custom root.")
    }
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
        command     => epp('windowspowershell/install_psmodule.ps1.epp', {
            'modulename'           => $modulename,
            'version'              => $module_version,
            'repository'           => $repository,
            'proxy'                => $windowspowershell::proxy_url,
            'use_proxy_credential' => $windowspowershell::proxy_use_credential,
        }),
        unless      => epp('windowspowershell/check_psmodule.ps1.epp', {
            'module_dir' => $module_dir,
            'modulename' => $modulename,
            'version'    => $module_version,
        }),
        provider    => powershell,
        environment => $windowspowershell::proxy_environment,
        timeout     => 900,
        logoutput   => on_failure,
        require     => Exec['windowspowershell install nuget provider'],
      }
      $installed_by = Exec["windowspowershell install ${name}"]
    } else {
      # Shared by every version of the same module, hence ensure_resource.
      ensure_resource('file', $module_dir, {
          'ensure'  => 'directory',
          'require' => File[$windowspowershell::normalized_module_root],
      })

      file { "${module_dir}\\${module_version}":
        ensure  => directory,
        recurse => true,
        source  => $source,
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
      # Import-Module -RequiredVersion is typed [version], which needs at
      # least major.minor, so a single-component pin such as `2` is
      # normalised to `2.0` for the profile fragment. This is the same
      # `^\d+$` -> `+.0` normalisation the version-check templates apply at
      # runtime before their `[version]` cast.
      $import_version = ($module_version =~ NotUndef and $module_version =~ /^\d+$/) ? {
        true    => "${module_version}.0",
        default => $module_version,
      }
      $import_content = epp('windowspowershell/import_external_module.ps1.epp', {
          'modulename' => $modulename,
          'version'    => $import_version,
      })

      # One fragment per managed profile, like windowspowershell::module:
      # concat assembles the header plus one Import-Module line per module.
      # The title keys on $name (not $modulename) and carries an
      # `external` prefix, so two resources sharing a modulename -- or an
      # in-house module with the same modulename -- never collide.
      $windowspowershell::profile_paths.each |$profile_path| {
        concat::fragment { "windowspowershell import external ${name} in ${profile_path}":
          target  => $profile_path,
          order   => '60',
          content => $import_content,
        }
      }
    }
  }
}
