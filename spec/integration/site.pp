# Minimal real catalog for the Windows integration test (issue #84).
#
# Applied twice by tools/Test-PuppetApply.ps1 on windows-2022 and windows-2025:
# the first run converges, the second must report no changes. Everything is
# offline: both the in-house module bulk copy and the third-party module use
# the `source` backend served from the wps_integration fixture module, so no
# PowerShell Gallery or NuGet access is needed.
#
# It exercises what rspec-puppet and the offline script replays cannot: a real
# agent compiling this catalog, ordering File/Exec/Concat resources, firing the
# manifest-regeneration notifies, and detecting duplicate resources.
# Backslashes on purpose: update_manifest.ps1.epp derives the NestedModules
# entries with a plain string Replace of the module path, so a forward-slashed
# module_root would leave absolute paths in the manifest. Backslashes keep the
# entries relative (Functions\...), like the runtime smoke test's root.
class { 'windowspowershell':
  module_root     => 'C:\wps-int\Modules',
  manage_profiles => true,
}

# In-house module deployed by bulk copy (`source`): covers the recursive
# purging File copy, the root module, the manifest witness, the
# create/update/unblock Exec chain and its ordering.
windowspowershell::module { 'WpsInt':
  version           => '1.0',
  companyname       => 'CI',
  author            => 'CI',
  source            => 'puppet:///modules/wps_integration/WpsInt',
  import_in_profile => true,
}

# Single script deployed by content: covers the per-script File resource and
# its notify of the shared manifest-regeneration Exec.
windowspowershell::script { 'Get-WpsIntHello':
  modulename => 'WpsInt',
  content    => "function Get-WpsIntHello { 'hello' }\n",
}

# Third-party module deployed by file copy (`source` backend): covers the
# versioned File copy and the purge of side-by-side versions without touching
# PowerShellGet, NuGet or any repository.
windowspowershell::external_module { 'WpsIntCopied':
  ensure => '1.2.3',
  source => 'puppet:///modules/wps_integration/WpsIntCopied/1.2.3',
}
