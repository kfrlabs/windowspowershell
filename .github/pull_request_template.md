## What does this PR do?

<!-- Link the issue(s): Closes #... -->

## Checklist

- [ ] `bundle exec rake syntax lint metadata_lint rubocop` passes
- [ ] `bundle exec rake parallel_spec` passes
- [ ] Rendered PowerShell parses under Windows PowerShell 5.1 and PowerShell 7
      (`tools/Test-RenderedPowerShell.ps1`) and PSScriptAnalyzer is clean
- [ ] `REFERENCE.md` regenerated if Puppet strings changed
      (`bundle exec rake strings:generate:reference`)
- [ ] `CHANGELOG.md` updated if user-visible
- [ ] Breaking change flagged with `**Breaking` in its `CHANGELOG.md` entry, if any
      (see [Stability policy](README.md#stability-policy))
