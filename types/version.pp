# A PowerShell module version: up to four dot-separated numbers, the shape
# `New-ModuleManifest` and `[version]` accept.
#
# Being digits and dots only, it is also safe to interpolate into a
# single-quoted PowerShell string and into a directory name.
type Windowspowershell::Version = Pattern[/\A\d+(\.\d+){0,3}\z/]
