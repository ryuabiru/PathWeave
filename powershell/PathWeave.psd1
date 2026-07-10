@{
    RootModule = 'PathWeave.psm1'
    ModuleVersion = '0.1.0'
    GUID = '8b8a0a75-e6e2-4f98-9d27-bfd63d47cc3d'
    Author = 'OpenAI'
    CompanyName = 'OpenAI'
    Copyright = '(c) OpenAI'
    Description = 'Fuzzy path completion support for PowerShell.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Enable-PathWeave',
        'Disable-PathWeave',
        'Invoke-PathWeaveCompletion',
        'Get-PathWeaveConfig',
        'Set-PathWeaveConfig'
    )
}
