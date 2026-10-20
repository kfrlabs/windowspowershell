# Files are unblocked at deploy time by Puppet (one refresh-only
# Exec['windowspowershell unblock-files <module name>'] per in-house module),
# not on every import, so this module does no per-session work beyond
# exporting its members.
Export-ModuleMember -Cmdlet * -Function * -Alias * -Variable *
