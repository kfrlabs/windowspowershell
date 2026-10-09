# A single path component: a script, folder or module name.
#
# Two properties are guaranteed, and the module relies on both:
#
# * It names one component and cannot escape its parent directory. The path
#   separators are excluded, and a name made only of dots is refused along with
#   every other name ending in a dot.
# * It is safe to interpolate into a single-quoted PowerShell string. The
#   apostrophe is the only character able to end such a string -- the backtick
#   and `$` are literal inside it -- so excluding the apostrophe is what keeps
#   the generated scripts free of injection.
#
# The remaining exclusions are what Windows itself refuses in a file name: the
# reserved characters, control characters, a trailing dot or space, and more
# than 255 characters in a single path component.
type Windowspowershell::Name = Pattern[/\A[^\\\/:*?"<>|'\x00-\x1F]{0,254}[^\\\/:*?"<>|'\x00-\x1F. ]\z/]
