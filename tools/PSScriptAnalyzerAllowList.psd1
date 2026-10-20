# Findings that are understood and accepted. An entry only matches when the
# rule, the file name (wildcard) and the offending source line (regex) all do.
@{
    Allow = @(
        @{
            # Building a PSCredential from a string is the only way to hand a
            # proxy password to Install-Module. The secret is read from the Exec
            # environment (WPS_PROXY_PASSWORD), never from the rendered text.
            Rule = 'PSAvoidUsingConvertToSecureStringWithPlainText'
            File = '*install_*'
            Line = '^\$secure = ConvertTo-SecureString \$env:WPS_PROXY_PASSWORD -AsPlainText -Force$'
        }
    )
}
