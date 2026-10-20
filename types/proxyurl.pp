# A proxy URL that is safe to embed in a single-quoted PowerShell string.
#
# Stdlib::HTTPUrl accepts anything after the scheme, an apostrophe included. The
# proxy is interpolated between single quotes in the generated scripts, which
# the agent runs as SYSTEM, so this alias keeps the `http://` or `https://`
# scheme requirement and refuses whatever could end the quoted string: the ASCII
# apostrophe, the typographic single quotes that PowerShell also treats as
# quote characters (U+2018 to U+201B), control characters and whitespace.
#
# Credentials embedded in the URL (`http://user:pass@host`) still match. That
# form is deprecated in favour of `proxy_credential`, but it is not refused here.
type Windowspowershell::Proxyurl = Pattern[/\A(?i:https?):\/\/[^'\u2018-\u201B\x00-\x1F\s]+\z/]
