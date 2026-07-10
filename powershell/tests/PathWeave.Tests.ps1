Import-Module "$PSScriptRoot/../PathWeave.psd1" -Force

Describe 'ConvertTo-PathWeaveInsertionText' {
    It 'quotes paths with spaces' {
        InModuleScope PathWeave {
            ConvertTo-PathWeaveInsertionText -Path '.\My Inbox' -Kind 'directory' | Should -Be "'.\My Inbox\'"
        }
    }

    It 'escapes single quotes' {
        InModuleScope PathWeave {
            ConvertTo-PathWeaveInsertionText -Path ".\Bob's Notes" -Kind 'file' | Should -Be "'.\Bob''s Notes'"
        }
    }
}

Describe 'Configuration' {
    It 'updates executable path' {
        Set-PathWeaveConfig -Executable 'pwv.exe'
        (Get-PathWeaveConfig).Executable | Should -Be 'pwv.exe'
    }
}
