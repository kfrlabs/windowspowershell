# Security Policy

## Supported Versions

Only the latest `3.x` release of `kfrlabs-windowspowershell` is supported
with security updates.

| Version | Supported                        |
| ------- | ---------------------------------- |
| 3.x     | :white_check_mark:                 |
| 2.x     | :white_check_mark: until 2027-01-30 |
| < 2.0   | :x:                                |

Only the latest major line gets new features; 2.x receives security fixes
until 2027-01-30, then reaches end of life.

> **Note:** 2.x security fixes continue until 2027-01-30.

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
