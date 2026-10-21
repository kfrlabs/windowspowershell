# A script base name, without the `.ps1` extension.
#
# Same guarantees as Windowspowershell::Name (single path component, safe to
# interpolate into a single-quoted PowerShell string, not a Windows reserved
# device name), plus one: a trailing `.ps1`/`.psm1` (any case) is refused
# (issue #56). The module appends `.ps1` itself, so `Get-Foo.ps1` would deploy
# `Get-Foo.ps1.ps1` exporting a broken function name. Dots elsewhere stay
# legitimate (`Get-Example.v2`).
type Windowspowershell::Scriptname = Pattern[/\A(?!(?i:.*\.psm?1)\z)(?!(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])[ ]*(?:\..*)?\z)[^\\\/:*?"<>|'\u2018-\u201B\x00-\x1F]{0,254}[^\\\/:*?"<>|'\u2018-\u201B\x00-\x1F. ]\z/]
