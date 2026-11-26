@{
    IncludeRules = @('PSUseConstrainedLanguageMode')
    Rules = @{
        PSUseConstrainedLanguageMode = @{
            Enable = $true
            IgnoreSignatures = $true
        }
    }
}
