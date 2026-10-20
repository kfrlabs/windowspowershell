# The machine-wide PowerShell module root, e.g. the parent of every in-house
# module folder this class lays out.
#
# It composes two constraints that Puppet, lacking an intersection type, cannot
# express separately:
#
# * The shape of an absolute Windows path, exactly as Stdlib::Windowspath
#   anchors it at the start: a drive letter, a UNC share, or a `\\?\` prefix.
# * Safety inside a single-quoted PowerShell string. `$module_root` feeds
#   `$module_path`, which is interpolated between single quotes in the manifest
#   template, so the apostrophe -- the only character able to end such a string
#   -- and the control characters are refused, here and inside the UNC server
#   and share segments too.
#
# The paths derived from it are safe by construction. Other values that reach a
# PowerShell string, such as the proxy URL, are constrained by their own type
# (see Windowspowershell::Proxyurl).
type Windowspowershell::Rootpath = Pattern[/\A(?:[A-Za-z]:[\\\/]|[\\\/][\\\/][^\\\/'\x00-\x1F]+[\\\/][^\\\/'\x00-\x1F]+|[\\\/][\\\/]\?[\\\/][^\\\/'\x00-\x1F]+)[^'\x00-\x1F]*\z/]
