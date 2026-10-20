# @summary Builds a custom per-node PowerShell module dynamically from Puppet sources.
#
# One resource is one module identity: its manifest (`.psd1`) is regenerated
# by a shared, refresh-only `Exec`, namespaced to this module's name, that
# every `windowspowershell::script { ..., modulename => <this title> }`
# notifies. A site that needs several in-house modules declares one
# `windowspowershell::module` per module name; nothing here is a
# module-wide singleton any more.
#
# A `windowspowershell::script` does not create its module: the module has to
# be declared with this resource (`windowspowershell::module { 'Acme': }` is
# enough to get every default), or the script fails to compile with a message
# naming the missing module. Add `version`, `companyname` or `author` only to
# override a default. Order only matters across scopes: a define body is
# evaluated after the scope that declared it, so declaring this resource before
# or after the scripts **in the same class** is fine. Declared from a scope that
# is evaluated after a script's body (a define nested deeper), it is not visible
# to that script yet and the script fails. Declare it from a class evaluated
# first (for example the profile class that `include`s the one declaring the
# scripts) to avoid that.
#
# The resource title is the in-house module name: this is the value every
# `windowspowershell::script` must pass as its own `modulename` to land its
# scripts here. Unlike `windowspowershell::external_module` (third-party, where several
# resource titles may legitimately share a target module), one
# `windowspowershell::module` resource is the one and only build of
# that module identity: the manifest, the root module file and the Functions
# directory are singletons, so declaring the same module name twice is a
# genuine conflict and fails to compile like any other duplicate resource
# declaration, rather than being silently merged.
#
# @param version
#   Version folder the module is installed under, and the ModuleVersion written
#   into the generated manifest. Defaults to `1.0`. Requires at least two
#   dot-separated components: a single number such as `1` is rejected at compile
#   time because PowerShell's `[version]` type, which `-ModuleVersion` casts to,
#   requires both a major and a minor version.
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
#   `manage_pwsh_profile` on the main class). Defaults to `true`, but the
#   import is often unnecessary: the module is under the machine-wide module
#   directory and exports its functions by name, so PowerShell auto-loads it on
#   first use, while the profile import adds to the startup time of every
#   session. Keep it when the aliases or variables the module defines are
#   needed from the start of the session. A failed import prints a warning.
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
# @param purge_versions
#   Whether to remove versions of the module other than the one in `version`.
#   Co-managing one modulename from both `windowspowershell::module` and
#   `windowspowershell::external_module` requires `purge_versions => false` on
#   one side, or each purge removes the other side's version.
#   The purge reuses the same numeric comparison as
#   `windowspowershell::external_module`: missing segments count as zero, so
#   pin `2.3` also keeps a `2.3.0` folder left behind by an earlier layout,
#   and a folder that does not parse as `[version]` is kept, never purged.
#
# @example Declare a module with non-default identity, then deploy scripts into it
#   windowspowershell::module { 'Acme':
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
#   windowspowershell::module { 'Acme':
#     source => 'puppet:///modules/profile/acme-scripts',
#   }
define windowspowershell::module (
  Windowspowershell::Moduleversion $version = '1.0',
  Windowspowershell::Psstring $companyname = 'Unknown',
  Windowspowershell::Psstring $author = 'Unknown',
  Boolean $import_in_profile = true,
  Optional[String[1]] $source = undef,
  Boolean $purge_versions = true,
) {
  include windowspowershell

  # The title *is* the module identity (see the class summary above for why
  # there is no separate modulename parameter). assert_type gives it the same
  # validation, and the same compile-time error, that a typed parameter would:
  # a title that cannot safely reach a path or a single-quoted PowerShell
  # string fails the catalogue here rather than further down.
  $modulename = assert_type(Windowspowershell::Name, $title) |$expected, $actual| {
    fail("Windowspowershell::Module[${title}]: title expects a match for ${expected}, got ${actual}")
  }

  # Every path this module's identity needs, derived here once, the same way
  # the main class used to derive them for the single module it owned.
  $module_dir             = "${windowspowershell::module_root}\\${modulename}"
  $module_path            = "${module_dir}\\${version}"
  $functions_path         = "${module_path}\\Functions"
  $rootmodule_path        = "${module_path}\\${modulename}.psm1"
  $manifest_path          = "${module_path}\\${modulename}.psd1"
  $manifest_witness_path  = "${module_path}\\.manifest-params"

  # Deterministic manifest GUID. New-ModuleManifest invents a random GUID when
  # none is passed, so the .psd1 would get a new module identity on every
  # regeneration. Deriving it from the module name alone keeps the identity
  # stable across runs, and across versions: PowerShell identifies a module by
  # name plus GUID and expects the GUID to stay the same from one version of a
  # module to the next, so it must not change when `version` is bumped.
  $manifest_guid = fqdn_uuid($modulename)

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
        'module_version' => $version,
        'guid'           => $manifest_guid,
    })

    # Witness of the manifest parameters. Its content is a pure function of
    # $manifest_command (author, companyname, version, guid, paths and any
    # flag a future release adds), so a change in any of them changes the file
    # and fires the refresh below. A refresh-only Exec never runs on a change
    # of its own `command`, and no other resource changes when only `author`
    # or `companyname` does, so without this file the .psd1 would stay stale
    # indefinitely. A missing or hand-edited witness is rewritten the same way,
    # which re-runs the manifest build.
    $manifest_witness = join([
        "# Managed by Puppet (windowspowershell::module ${modulename}). Do not edit.",
        '# SHA-256 of the manifest build command; a change regenerates the .psd1.',
        sha256($manifest_command),
        '',
    ], "\n")

    file { $manifest_witness_path:
      ensure  => file,
      content => $manifest_witness,
      notify  => [
        Exec["windowspowershell update-manifest ${modulename}"],
        Exec["windowspowershell unblock-files ${modulename}"],
      ],
    }

    # Build the manifest once per version folder: `creates` only tests that the
    # .psd1 exists, so a manifest that is present but stale or corrupt is left
    # alone -- the witness above and `update-manifest` below are what rebuild it.
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
    # `-LiteralPath` is required because a module name or `module_root` may
    # legally hold `[` and `]`, which `-Path` reads as a wildcard character
    # class and so matches nothing, silently leaving the whole tree blocked.
    exec { "windowspowershell unblock-files ${modulename}":
      command     => "Get-ChildItem -LiteralPath '${module_path}' -Recurse -File | Unblock-File",
      provider    => powershell,
      refreshonly => true,
      logoutput   => on_failure,
    }

    # Purging by directory rather than Uninstall-Module on purpose: it also
    # catches versions deployed before the manifest carried the right
    # ModuleVersion, which PowerShellGet has no record of.
    if $purge_versions {
      exec { "windowspowershell purge other in-house versions of ${modulename}":
        command   => epp('windowspowershell/purge_psmodule_versions.ps1.epp', {
            'module_dir' => $module_dir,
            'version'    => $version,
        }),
        unless    => epp('windowspowershell/check_psmodule_versions.ps1.epp', {
            'module_dir' => $module_dir,
            'version'    => $version,
        }),
        provider  => powershell,
        timeout   => 300,
        logoutput => on_failure,
        require   => [
          Exec["windowspowershell update-manifest ${modulename}"],
          Exec["windowspowershell unblock-files ${modulename}"],
        ],
      }
    }

    File[$module_dir]
    -> File[$module_path]
    -> File[$functions_path]
    -> File[$rootmodule_path]
    -> File[$manifest_witness_path]
    -> Exec["windowspowershell create-manifest ${modulename}"]
    -> Exec["windowspowershell update-manifest ${modulename}"]
    -> Exec["windowspowershell unblock-files ${modulename}"]

    if $import_in_profile {
      # One fragment per managed profile: concat assembles the header
      # (owned by windowspowershell::config) plus one Import-Module line
      # per module, so several modules no longer overwrite each other.
      $windowspowershell::profile_paths.each |$profile_path| {
        concat::fragment { "windowspowershell import ${modulename} in ${profile_path}":
          target  => $profile_path,
          order   => '50',
          content => epp('windowspowershell/import_module.ps1.epp', {
              'manifest_path' => $manifest_path,
          }),
        }
      }
    }
  }
}
