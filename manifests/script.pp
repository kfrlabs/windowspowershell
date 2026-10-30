# @summary Deploys a PowerShell script as a function of an in-house module.
#
# The script is written under the target module's `Functions` directory and
# notifies that module's shared manifest-regeneration Exec, so it is exported
# on the next PowerShell session. Removing it is the same resource with
# `ensure => absent`.
#
# On nodes without long-path support the script path
# (`<module_root>\<module>\<version>\Functions\<folder>\<script>.ps1`) must stay
# under 260 characters (Windows `MAX_PATH`, terminating NUL included). With
# `ensure => present`, a longer path applies the `path_length_policy` class
# parameter (`warn` by default, `fail` to fail compilation, `ignore` to stay
# silent), unless the node reports long paths enabled (the
# `long_paths_enabled` fact is `true`), which silences the check.
#
# @param modulename
#   Name of the in-house module (a `windowspowershell::module`
#   resource) this script is deployed into. Mandatory: there is no default
#   module any more, so every script has to say where it is going. The module
#   named here must be declared with `windowspowershell::module`: this define
#   does not create it, and fails to compile when it is missing (see the
#   README for the declaration order).
# @param ensure
#   Whether the script should be present or absent. A script with
#   `ensure => present` targeting a module declared with
#   `ensure => absent` fails compilation (issue #88): retire the script
#   (`ensure => absent`) first, or restore the module. A script with
#   `ensure => absent` targeting an absent module only removes its own file
#   without notifying the manifest refresh, which no longer exists.
# @param scriptname
#   Base name of the script, without the `.ps1` extension. Defaults to the
#   resource title. This is also the name of the exported PowerShell function:
#   the deployed `<scriptname>.ps1` must define a top-level
#   `function <scriptname>` (name contract, issue #135 step 1), otherwise the
#   manifest build fails closed with
#   `CONTRACT ERROR <file>: no function named '<scriptname>' defined in file`
#   and leaves the existing `.psd1` untouched. Base names must also be unique
#   across the module's `Functions/` tree (case-insensitive, so `Foo.ps1` and
#   `Foo.psm1` collide): a duplicate fails the manifest build the same way.
#   A trailing `.ps1`/`.psm1` is refused: the module appends `.ps1` itself, so
#   `Get-Foo.ps1` would deploy `Get-Foo.ps1.ps1` exporting a broken function
#   name. Dots elsewhere stay legitimate (`Get-Example.v2`).
# @param folder
#   Optional sub-folder under `Functions`, to group scripts by domain.
# @param content
#   Literal content of the script. Mutually exclusive with `source`.
# @param source
#   Puppet file source for the script. Mutually exclusive with `content`.
# @param bom
#   UTF-8 BOM handling for `content`. `auto` (default) prefixes U+FEFF only
#   when the content holds non-ASCII characters and has no BOM yet; `always`
#   prefixes U+FEFF whenever content is given and has no BOM yet; `never`
#   leaves the content untouched. Content read from `source` is never altered.
#
# @example
#   windowspowershell::module { 'Acme': }
#
#   windowspowershell::script { 'Get-WUParams':
#     modulename => 'Acme',
#     folder     => 'Windowsupdate',
#     content    => template('windowsupdate/windowspowershell/Get-WUParams.ps1.erb'),
#   }
#
# @example Retire a script that is no longer shipped
#   windowspowershell::module { 'Acme': }
#
#   windowspowershell::script { 'Get-OldThing':
#     modulename => 'Acme',
#     ensure     => absent,
#   }
define windowspowershell::script (
  Windowspowershell::Name $modulename,
  Enum['present', 'absent'] $ensure = 'present',
  Windowspowershell::Scriptname $scriptname = $name,
  Optional[Windowspowershell::Name] $folder = undef,
  Optional[String[1]] $content = undef,
  Optional[String[1]] $source = undef,
  Enum['auto', 'always', 'never'] $bom = 'auto',
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

  # This define does not create the module it names. An implicit module made
  # the version depend on declaration order: an explicit module declared after
  # it died with a bare Puppet "Duplicate declaration" (issue #46). The module
  # has to be declared explicitly, and a missing one fails here with a message
  # that says so.
  #
  # Declaration order: Puppet evaluates a define's body lazily, after the
  # scope that declared it, so a windowspowershell::module written before OR
  # after this script in the same class/manifest is already in the catalogue by
  # now. One declared from a scope evaluated after this body (a define nested
  # one level deeper, say) is not visible yet and fails the same way.
  if !defined(Windowspowershell::Module[$modulename]) {
    fail("windowspowershell::script[${name}]: module '${modulename}' is not declared. Declare windowspowershell::module { '${modulename}': } (add version, companyname or author there to override a default), in the same class as this script or in a class evaluated before it: the script reads the module's version when its body is evaluated, so the module has to be in the catalogue by then.")
  }

  # getparam reads back the version this particular module identity resolved
  # to, since this define does not own that resource and must not guess its
  # path independently. It only sees explicitly set parameters, never the
  # define defaults, so a module left at its defaults reads as undef here.
  # Fall back to the $version default declared on windowspowershell::module,
  # which has to stay equal to this literal (a spec guards it). Same for
  # `ensure`: only an explicit `ensure => absent` reads back as absent.
  $module_version = pick(getparam(Windowspowershell::Module[$modulename], 'version'), '1.0')
  $module_ensure = pick(getparam(Windowspowershell::Module[$modulename], 'ensure'), 'present')
  if $module_ensure == 'absent' and $ensure == 'present' {
    fail("windowspowershell::script[${name}]: module '${modulename}' is absent (windowspowershell::module { '${modulename}': ensure => absent }): retire this script first (ensure => absent) or restore the module (ensure => present).")
  }
  $functions_path = "${windowspowershell::normalized_module_root}\\${modulename}\\${module_version}\\Functions"

  $script_folder = $folder ? {
    undef   => $functions_path,
    default => "${functions_path}\\${folder}",
  }
  $script_path = "${script_folder}\\${scriptname}.ps1"

  # Issue #115: over-limit script paths exceed Windows MAX_PATH (260
  # characters, terminating NUL included, hence 259). Issue #137 applies the
  # `path_length_policy` class parameter instead of warning unconditionally:
  # on a node reporting long paths enabled (the `long_paths_enabled` fact is
  # `true`) nothing is logged, whatever the policy is.
  $script_path_length = $script_path.length
  if $ensure == 'present' and $script_path_length > 259 {
    $script_folder_label = $folder ? {
      undef   => '(none)',
      default => "'${folder}'",
    }
    windowspowershell::check_path_length("windowspowershell::script[${name}]: the script path is ${script_path_length} characters, over the 259-character Windows MAX_PATH limit (module_root '${windowspowershell::normalized_module_root}', modulename '${modulename}', version '${module_version}', folder ${script_folder_label}, scriptname '${scriptname}'). Without long-path support on the node, deploying it fails with an opaque path error. Shorten module_root, modulename, version, folder or scriptname, or enable long paths on the node (LongPathsEnabled).")
  }

  # Issue #134: Windows PowerShell 5.1 decodes a BOM-less script as ANSI, so
  # non-ASCII content is mangled without a UTF-8 BOM (U+FEFF). `auto` adds it
  # only for non-ASCII content missing one; `always` adds it to any BOM-less
  # content; `never` keeps the previous behavior.
  $has_non_ascii = $content =~ NotUndef and $content =~ /[^\x00-\x7F]/
  $has_bom = $content =~ NotUndef and $content =~ /\A\uFEFF/
  $needs_bom = $content =~ NotUndef and $ensure == 'present' and $bom != 'never' and !$has_bom and ($bom == 'always' or $has_non_ascii)
  $effective_content = $needs_bom ? {
    true    => "\uFEFF${content}",
    default => $content,
  }

  if !$windowspowershell::supported {
    # No-op: the class declares nothing on this node, so there is no Functions
    # directory to write into and no Exec to notify.
  } elsif $ensure == 'present' {
    # The Functions directory itself belongs to windowspowershell::module;
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
      content => $effective_content,
      source  => $source,
      require => File[$script_folder],
      notify  => [
        Exec["windowspowershell update-manifest ${modulename}"],
        Exec["windowspowershell unblock-files ${modulename}"],
      ],
    }
  } else {
    # When the module itself is absent its manifest Execs no longer exist, so
    # an absent script only removes its own file and notifies nothing.
    $absent_notify = $module_ensure == 'absent' ? {
      true    => undef,
      default => Exec["windowspowershell update-manifest ${modulename}"],
    }
    file { $script_path:
      ensure => absent,
      notify => $absent_notify,
    }
  }
}
