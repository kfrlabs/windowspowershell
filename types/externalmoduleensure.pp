# Desired state of an external PowerShell module, mirroring the `package` type: a
# literal version pins that exact version, `present` accepts any version, and
# `absent` removes every version installed under the machine-wide (`AllUsers`)
# module directory and unregisters the module from PowerShellGet.
#
# `latest` is deliberately absent. Resolving it requires a `Find-Module` call
# on every Puppet run, and it lets two nodes end up on different versions
# depending on the day they last ran.
type Windowspowershell::Externalmoduleensure = Variant[
  Enum['present', 'absent'],
  Windowspowershell::Version,
]
