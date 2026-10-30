# Contributing to kfrlabs-windowspowershell

Contributions are welcome via GitHub issues and pull requests. This module is
maintained in the open; the steady state is defined by `TESTING.md` (how to
test) and `README.md` (what the module promises, including the
[Stability policy](README.md#stability-policy)).

## Issues

- Use the issue templates: a bug report needs the module version, the Puppet
  and Windows versions, what happened versus what was expected, and a minimal
  manifest reproducer.
- A feature request should say who needs it and what changes for existing
  catalogues (especially: does a default change, and if so, why it is worth
  a major release under the stability policy).

## Pull requests

Link the issue (`Closes #...`). Every PR must keep this checklist green:

- `bundle exec rake syntax lint metadata_lint rubocop` passes.
- `bundle exec rake parallel_spec` passes (rspec-puppet, Ruby 3.2 and 3.3).
- Rendered PowerShell parses under Windows PowerShell 5.1 and PowerShell 7
  (`tools/Test-RenderedPowerShell.ps1`) and PSScriptAnalyzer is clean.
- `REFERENCE.md` regenerated if Puppet strings changed
  (`bundle exec rake strings:generate:reference`).
- `CHANGELOG.md` updated if the change is user-visible.
- Breaking changes flagged with `**Breaking**` in their `CHANGELOG.md` entry
  (see [Stability policy](README.md#stability-policy)).

The per-PR Windows jobs (rendered PowerShell replay, double-apply
integration, repository backend, and the Pester version-compare suite) run
automatically; see `TESTING.md` for what each level proves and how to run the
Windows-only parts on a lab node.

## Release process

Releases are tags, not PRs: once `main` is green, a maintainer pushes a
`v*.*.*` tag matching `metadata.json`. `release.yml` verifies the tag
(CI `Test suite` green on that exact commit, `**Breaking` only on a major
bump) and publishes to the Forge. Do not push version tags from a PR branch.

## Code of conduct

By participating you agree to uphold the [Code of Conduct](CODE_OF_CONDUCT.md).
Report unacceptable behaviour via GitHub private vulnerability reporting or
by opening a (possibly private) issue to the maintainers.
