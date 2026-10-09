# Name of a PowerShell repository, as registered by `Register-PSRepository`
# and passed to `Install-Module -Repository`.
#
# Deliberately narrower than what PowerShellGet would accept: the value is
# interpolated into a single-quoted PowerShell string, so it is restricted to
# the characters real repository names use -- `PSGallery`, `Internal-Repo`,
# `nuget.local` -- and nothing that could end that string.
type Windowspowershell::Reponame = Pattern[/\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/]
