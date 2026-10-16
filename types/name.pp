# A single path component: a script, folder or module name.
#
# Three properties are guaranteed, and the module relies on all three:
#
# * It names one component and cannot escape its parent directory. The path
#   separators are excluded, and a name made only of dots is refused along with
#   every other name ending in a dot.
# * It is safe to interpolate into a single-quoted PowerShell string. The
#   apostrophe is the only character able to end such a string -- the backtick
#   and `$` are literal inside it -- so excluding the apostrophe is what keeps
#   the generated scripts free of injection.
# * It is not a Windows reserved device name. CON, PRN, AUX, NUL, COM1-9 and
#   LPT1-9 are refused case-insensitively, with or without an extension;
#   spaces between the stem and the extension do not save it either.
#
# The remaining exclusions are what Windows itself refuses in a file name: the
# reserved characters, control characters, a trailing dot or space, and more
# than 255 characters in a single path component.
type Windowspowershell::Name = Pattern[/\A(?!(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])[ ]*(?:\..*)?\z)[^\\\/:*?"<>|'\x00-\x1F]{0,254}[^\\\/:*?"<>|'\x00-\x1F. ]\z/]
