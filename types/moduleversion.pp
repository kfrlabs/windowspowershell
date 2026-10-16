# A PowerShell module version that New-ModuleManifest can actually write: two to
# four dot-separated numbers of at most nine digits each. That is the shape
# PowerShell's `[version]` type and its `-ModuleVersion` parameter accept -- a
# major and a minor component at minimum, every component within Int32 -- so the
# cast it performs cannot fail at Exec runtime.
#
# A single number such as `1` consists only of digits, so it slips past
# Windowspowershell::Version, and casting it to `[version]` throws. This alias
# rules that out at compile time instead.
#
# Leading zeros are still allowed, so `01.02` passes here and PowerShell reports
# the module as `1.2` while the folder keeps its `01.02` name.
type Windowspowershell::Moduleversion = Pattern[/\A\d{1,9}(\.\d{1,9}){1,3}\z/]