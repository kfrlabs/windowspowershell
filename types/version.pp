# A PowerShell module version: up to four dot-separated numbers.
#
# Deliberately looser than Windowspowershell::Moduleversion, which requires at
# least two components. This type serves windowspowershell::external_module,
# whose version reaches PowerShellGet's Install-Module -RequiredVersion as a
# plain string and is accepted there as it stands.
#
# It is not, however, safe for every consumer: the profile fragment also passes
# it to Import-Module -RequiredVersion, which is typed [Version]. A
# single-component version such as `1` therefore compiles but fails there at
# runtime, silently, because that fragment runs under -ErrorAction
# SilentlyContinue. Tightening this type is deliberately left to a separate
# change, which would break external_module catalogues.
#
# Being digits and dots only, it is also safe to interpolate into a
# single-quoted PowerShell string and into a directory name.
type Windowspowershell::Version = Pattern[/\A\d+(\.\d+){0,3}\z/]
