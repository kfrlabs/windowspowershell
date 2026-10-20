# Free text that ends up inside a single-quoted PowerShell string, such as the
# author or company written into the module manifest.
#
# Unlike Windowspowershell::Name this is not a path component, so spaces,
# dots and most punctuation are fine. Only what could break out of the quoted
# string is refused: the apostrophe, the typographic single quotes PowerShell
# also treats as quote characters (U+2018 to U+201B), and control characters.
type Windowspowershell::Psstring = Pattern[/\A[^'\u2018-\u201B\x00-\x1F]{1,255}\z/]
