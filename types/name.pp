# A single path component: a script, folder or module name.
#
# Three properties are guaranteed, and the module relies on all three:
#
# * It names one component and cannot escape its parent directory. The path
#   separators are excluded, and a name made only of dots is refused along with
#   every other name ending in a dot.
# * It is safe to interpolate into a single-quoted PowerShell string. What can
#   end such a string is the ASCII apostrophe and the typographic single quotes
#   PowerShell also treats as quote characters (U+2018 to U+201B) -- the
#   backtick and `$` are literal inside it -- so excluding those is what keeps
#   the generated scripts free of injection.
# * It is not a Windows reserved device name. CON, PRN, AUX, NUL, COM1-9 and
#   LPT1-9 are refused case-insensitively, with or without an extension;
#   spaces between the stem and the extension do not save it either.
#
# The remaining exclusions are what Windows itself refuses in a file name: the
# reserved characters, control characters, a trailing dot or space, and more
# than 255 characters in a single path component.
type Windowspowershell::Name = Pattern[/\A(?!(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])[ ]*(?:\..*)?\z)[^\\\/:*?"<>|'\u2018-\u201B\x00-\x1F]{0,254}[^\\\/:*?"<>|'\u2018-\u201B\x00-\x1F. ]\z/]
