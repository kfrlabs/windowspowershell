# A PowerShell module version: one to four dot-separated numbers of at most
# nine digits each.
#
# Deliberately looser than Windowspowershell::Moduleversion, which requires at
# least two components. This type serves windowspowershell::external_module,
# whose version reaches PowerShellGet's Install-Module -RequiredVersion as a
# plain string and is accepted there as it stands. A single-component pin
# such as `2` is therefore still accepted here; the profile fragment
# normalises it to `2.0` because Import-Module -RequiredVersion is typed
# [version], which needs at least major.minor.
#
# Each component is still limited to nine digits, like Moduleversion: every
# component is parsed as an Int32 by System.Version, so a tenth digit would
# overflow at Exec runtime instead of failing the catalogue at compile time.
#
# Being digits and dots only, it is also safe to interpolate into a
# single-quoted PowerShell string and into a directory name.
type Windowspowershell::Version = Pattern[/\A\d{1,9}(\.\d{1,9}){0,3}\z/]
