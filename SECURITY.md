# Security Policy

## Supported Versions

Only the latest `2.x` release of `kfrlabs-windowspowershell` is supported
with security updates.

| Version | Supported          |
| ------- | ------------------ |
| 2.x     | :white_check_mark: |
| < 2.0   | :x:                |

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability.

Use GitHub **Private vulnerability reporting** on this repository
(Security tab → Report a vulnerability) so the report stays private
until a fix is released.

Include, when possible:

- the module version and Puppet/Windows versions in use,
- a minimal manifest reproducing the issue,
- the impact (catalog leak, arbitrary code execution as `SYSTEM`, …).

You will receive an initial answer within a reasonable delay. If the
vulnerability is confirmed, a fix is prepared privately and released
as soon as possible, with credit in the CHANGELOG unless you prefer
to stay anonymous.
