# @summary Builds one in-house PowerShell module whose functions are the
#   `.ps1` scripts deployed by `windowspowershell::script`.
#
# One resource is one module identity: its manifest (`.psd1`) is regenerated
# by a shared, refresh-only `Exec`, namespaced to this module's name, that
# every `windowspowershell::script { ..., modulename => <this title> }`
# notifies. A site that needs several in-house modules declares one
# `windowspowershell::inhouse_module` per module name; nothing here is a
# module-wide singleton any more.
#
# A `windowspowershell::script` that names a module which was never declared
# explicitly gets one with every default, via `ensure_resource`. Declare this
# resource explicitly only when a default (`version`, `companyname` or
# `author`) needs overriding -- in which case it must be declared before the
# first `windowspowershell::script` that names it, since `ensure_resource`
# only fills in the gap when nothing has claimed the title yet.
#
# The resource title is the in-house module name: this is the value every
# `windowspowershell::script` must pass as its own `modulename` to land its
# scripts here. Unlike `windowspowershell::module` (third-party, where several
# resource titles may legitimately share a target module), one
# `windowspowershell::inhouse_module` resource is the one and only build of
# that module identity: the manifest, the root module file and the Functions
# directory are singletons, so declaring the same module name twice is a
# genuine conflict and fails to compile like any other duplicate resource
# declaration, rather than being silently merged.
#
# @param version
#   Version folder the module is installed under. Defaults to `1.0`.
# @param companyname
#   CompanyName field written into the generated module manifest. Defaults to
#   the neutral `Unknown`; override with the real company.
# @param author
#   Author field written into the generated module manifest. Defaults to the
#   neutral `Unknown`; a team or service identity is a better fit than a
#   person's name, since it stays meaningful over time.
# @param import_in_profile
#   Whether to add an `Import-Module` line for this module to every profile
#   file managed by `windowspowershell::config` (see `manage_profiles` /
#   `manage_pwsh_profile` on the main class).
# @param source
#   Optional Puppet file source bulk-deploying every script under it straight
#   into `Functions`, one recursive, **purging** copy preserving the source
#   tree -- the "dynamic" way to build a module: drop a new `.ps1` under that
#   source directory (optionally in a sub-folder) and it ships on the next
#   Puppet run, with no Puppet code change and no per-script resource. Because
#   this copy purges, it takes over the *whole* `Functions` directory: do not
#   mix it with `windowspowershell::script` resources naming the same module,
#   since this copy would remove what they manage (and vice versa) on the
#   next run. Left `undef` (the default), nothing is copied in bulk and
#   `Functions` is only ever populated by individual `windowspowershell::script`
#   resources, which remains the right choice for dynamic content (e.g. a
#   template).
#
# @example Declare a module with non-default identity, then deploy scripts into it
#   windowspowershell::inhouse_module { 'Acme':
#     version     => '1.2',
#     companyname => 'Acme Corp',
#     author      => 'Platform Team',
#   }
#
#   windowspowershell::script { 'Get-DiskUsage':
#     modulename => 'Acme',
#     content    => file('profile/powershell/Get-DiskUsage.ps1'),
#   }
#
# @example Build a module dynamically from a whole directory of scripts
#   windowspowershell::inhouse_module { 'Acme':
#     source => 'puppet:///modules/profile/acme-scripts',
#   }
define windowspowershell::inhouse_module (
  Windowspowershell::Version $version = '1.0',
  Windowspowershell::Psstring $companyname = 'Unknown',
  Windowspowershell::Psstring $author = 'Unknown',
  Boolean $import_in_profile = true,
  Optional[String[1]] $source = undef,
) {
  include windowspowershell

  # The title *is* the module identity (see the class summary above for why
  # there is no separate modulename parameter). assert_type gives it the same
  # validation, and the same compile-time error, that a typed parameter would:
  # a title that cannot safely reach a path or a single-quoted PowerShell
  # string fails the catalogue here rather than further down.
  $modulename = assert_type(Windowspowershell::Name, $title) |$expected, $actual| {
    fail("Windowspowershell::Inhouse_module[${title}]: title expects a match for ${expected}, got ${actual}")
  }

  # Every path this module's identity needs, derived here once, the same way
  # the main class used to derive them for the single module it owned.
  $module_dir      = "${windowspowershell::module_root}\\${modulename}"
  $module_path     = "${module_dir}\\${version}"
  $functions_path  = "${module_path}\\Functions"
  $rootmodule_path = "${module_path}\\${modulename}.psm1"
  $manifest_path   = "${module_path}\\${modulename}.psd1"

  # Deterministic manifest GUID. New-ModuleManifest invents a random GUID when
  # none is passed, so the .psd1 would get a new module identity on every
  # regeneration. Deriving it from name+version keeps the identity stable
  # across runs without asking the user for anything.
  $manifest_guid = fqdn_uuid("${modulename}-${version}")

  if $windowspowershell::supported {
    file { $module_dir:
      ensure  => directory,
      require => File[$windowspowershell::module_root],
    }

    file { $module_path:
      ensure => directory,
    }

    # With a source, this single recursive, purging copy is both the
    # directory creation and the bulk script deployment: a new script only
    # needs to be dropped under that source (optionally in a sub-folder, to
    # land under a matching Functions/ sub-folder), no Puppet code change and
    # no per-script declaration. Without one, this only creates the directory
    # and individual windowspowershell::script resources populate it, which
    # is required for callers that need dynamic content (e.g. a template).
    file { $functions_path:
      ensure  => directory,
      recurse => $source =~ NotUndef,
      purge   => $source =~ NotUndef,
      source  => $source,
      notify  => $source =~ NotUndef ? {
        true    => [
          Exec["windowspowershell update-manifest ${modulename}"],
          Exec["windowspowershell unblock-files ${modulename}"],
        ],
        default => undef,
      },
    }

    # Root module: dot-sources nothing itself. The generated manifest lists
    # every .ps1 under Functions/ as a NestedModule, so PowerShell loads them
    # all.
    file { $rootmodule_path:
      ensure  => file,
      content => file('windowspowershell/rootmodule.psm1'),
      notify  => [
        Exec["windowspowershell update-manifest ${modulename}"],
        Exec["windowspowershell unblock-files ${modulename}"],
      ],
    }

    # One command, two triggers. A stable -Guid (derived above) keeps the
    # module identity constant across regenerations.
    $manifest_command = epp('windowspowershell/update_manifest.ps1.epp', {
        'module_path'    => $module_path,
        'functions_path' => $functions_path,
        'manifest_path'  => $manifest_path,
        'module_name'    => $modulename,
        'company_name'   => $companyname,
        'author'         => $author,
        'guid'           => $manifest_guid,
    })

    # Self-heal: rebuild the manifest whenever it is missing, independent of
    # any notification. `creates` makes it a no-op once the .psd1 exists, so a
    # run where nothing changed stays no-op, while a manually deleted or
    # corrupted manifest is recreated on the next run without any script
    # having changed.
    exec { "windowspowershell create-manifest ${modulename}":
      command   => $manifest_command,
      provider  => powershell,
      creates   => $manifest_path,
      logoutput => on_failure,
    }

    # Refresh-only: notified by the root module and by every
    # windowspowershell::script naming this module, and refreshed once per
    # transaction no matter how many scripts changed.
    exec { "windowspowershell update-manifest ${modulename}":
      command     => $manifest_command,
      provider    => powershell,
      refreshonly => true,
      logoutput   => on_failure,
    }

    # Unblock the module tree at deploy time rather than on every import, and
    # at most once per transaction no matter how many files changed. `-File`
    # keeps directories out of the pipeline, which Unblock-File cannot act on.
    exec { "windowspowershell unblock-files ${modulename}":
      command     => "Get-ChildItem -Path '${module_path}' -Recurse -File | Unblock-File",
      provider    => powershell,
      refreshonly => true,
      logoutput   => on_failure,
    }

    File[$module_dir]
    -> File[$module_path]
    -> File[$functions_path]
    -> File[$rootmodule_path]
    -> Exec["windowspowershell create-manifest ${modulename}"]
    -> Exec["windowspowershell update-manifest ${modulename}"]
    -> Exec["windowspowershell unblock-files ${modulename}"]

    if $import_in_profile {
      # Amend the profile skeletons owned by windowspowershell::config with a
      # collector, so the Import-Module line lands on the File resources
      # themselves. A collector override is order-independent (unlike
      # ensure_resource) and keeps working no matter which manifest first
      # pulls in the windowspowershell class.
      $windowspowershell::profile_paths.each |$profile_path| {
        File <| title == $profile_path |> {
          content => epp('windowspowershell/import_inhouse_module.ps1.epp', {
              'manifest_path' => $manifest_path,
          }),
        }
      }
    }
  }
}
