$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../PathWeave.psd1" -Force

$module = Get-Module PathWeave

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        $Actual,
        [Parameter(Mandatory)]
        $Expected,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Actual -cne $Expected) {
        throw "$Message`nExpected: $Expected`nActual:   $Actual"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-PrivatePathWeave {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [object[]]$ArgumentList = @()
    )

    & $module $Name @ArgumentList
}

function New-TempPathWeaveWorkspace {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $root | Out-Null
    $root
}

function Reset-PathWeaveTabCycleState {
    Invoke-PrivatePathWeave 'Clear-PathWeaveTabState'
}

$tests = @(
    @{
        Name = 'quotes paths with spaces'
        Script = {
            $result = Invoke-PrivatePathWeave 'ConvertTo-PathWeaveInsertionText' @('.\My Inbox', 'directory')
            Assert-Equal $result "'.\My Inbox\'" 'Directory path with spaces should be quoted and keep trailing slash.'
        }
    },
    @{
        Name = 'escapes single quotes'
        Script = {
            $result = Invoke-PrivatePathWeave 'ConvertTo-PathWeaveInsertionText' @(".\Bob's Notes", 'file')
            Assert-Equal $result "'.\Bob''s Notes'" 'Single quotes should be escaped for PowerShell insertion.'
        }
    },
    @{
        Name = 'updates configuration'
        Script = {
            Set-PathWeaveConfig -Executable 'pwv-test.exe' -MaxResults 12 -MaxDepth 6 -IncludeHidden $true -FollowLinks $true -EnableTabIntegration $true
            $config = Get-PathWeaveConfig
            Assert-Equal $config.Executable 'pwv-test.exe' 'Executable should update.'
            Assert-Equal $config.MaxResults 12 'MaxResults should update.'
            Assert-Equal $config.MaxDepth 6 'MaxDepth should update.'
            Assert-True $config.IncludeHidden 'IncludeHidden should update.'
            Assert-True $config.FollowLinks 'FollowLinks should update.'
            Assert-True $config.EnableTabIntegration 'EnableTabIntegration should update.'
        }
    },
    @{
        Name = 'extracts token from quoted argument'
        Script = {
            $state = Invoke-PrivatePathWeave 'Get-PathWeaveTokenStateFromBuffer' @('nvim ''My Inbox''', 14)
            Assert-Equal $state.Query 'My Inbox' 'Quoted token should be extracted without quote characters.'
            Assert-Equal $state.Start 5 'Quoted token start offset should match parser token.'
            Assert-Equal $state.Length 10 'Quoted token length should match token span.'
        }
    },
    @{
        Name = 'extracts bare token near cursor'
        Script = {
            $state = Invoke-PrivatePathWeave 'Get-PathWeaveTokenStateFromBuffer' @('rg keyword inbox', 16)
            Assert-Equal $state.Query 'inbox' 'Bare token should be extracted.'
            Assert-Equal $state.Start 11 'Bare token start offset should be correct.'
            Assert-Equal $state.Length 5 'Bare token length should be correct.'
        }
    },
    @{
        Name = 'resolves local release binary'
        Script = {
            $resolved = Invoke-PrivatePathWeave 'Resolve-PathWeaveExecutable' @('pwv')
            Assert-True (Test-Path $resolved) 'Executable resolver should return an existing path.'
        }
    },
    @{
        Name = 'replaces bare argument in full command line'
        Script = {
            $selected = [pscustomobject]@{
                path = '.\00-Inbox\'
                kind = 'directory'
            }
            $result = Invoke-PrivatePathWeave 'Apply-PathWeaveCompletionToBuffer' @('nvim inbox', 10, $selected)
            Assert-Equal $result.Line 'nvim .\00-Inbox\' 'Bare argument should be replaced in-place.'
            Assert-Equal $result.Cursor 16 'Cursor should move to the end of the inserted path.'
            Assert-Equal $result.Start 5 'Replacement should start at the argument offset.'
            Assert-Equal $result.Length 5 'Replacement should cover the original token.'
        }
    },
    @{
        Name = 'replaces quoted argument with quoted completion'
        Script = {
            $selected = [pscustomobject]@{
                path = '.\My Inbox\'
                kind = 'directory'
            }
            $line = 'Get-Content ''my in'''
            $result = Invoke-PrivatePathWeave 'Apply-PathWeaveCompletionToBuffer' @($line, ($line.Length - 1), $selected)
            Assert-Equal $result.Line "Get-Content '.\My Inbox\'" 'Quoted argument should stay a valid PowerShell string after replacement.'
            Assert-Equal $result.Replacement "'.\My Inbox\'" 'Replacement should be correctly quoted.'
        }
    },
    @{
        Name = 'replaces path-like token without touching later arguments'
        Script = {
            $selected = [pscustomobject]@{
                path = '.\notes\00-Inbox.md'
                kind = 'file'
            }
            $result = Invoke-PrivatePathWeave 'Apply-PathWeaveCompletionToBuffer' @('Copy-Item .\notes\inbox .\backup\', 23, $selected)
            Assert-Equal $result.Line 'Copy-Item .\notes\00-Inbox.md .\backup\' 'Only the active argument should change.'
        }
    },
    @{
        Name = 'formats fallback menu labels with kind and hotkey'
        Script = {
            $result = [pscustomobject]@{
                path = '.\Cargo.toml'
                display = 'Cargo.toml'
                kind = 'file'
            }
            $label = Invoke-PrivatePathWeave 'Format-PathWeaveChoiceLabel' @($result, 0)
            $help = Invoke-PrivatePathWeave 'Format-PathWeaveChoiceHelp' @($result)
            Assert-Equal $label '&1 [file] Cargo.toml' 'Fallback menu should show a hotkey and entry kind.'
            Assert-Equal $help 'Insert .\Cargo.toml' 'Fallback menu should show the inserted path as help text.'
        }
    },
    @{
        Name = 'prefers standard Tab for known command completions'
        Script = {
            $action = Invoke-PrivatePathWeave 'Get-PathWeaveTabAction' @('Get-ChildIte', 12)
            Assert-Equal $action 'Standard' 'Known command completions should stay on standard Tab behavior.'
        }
    },
    @{
        Name = 'falls back to PathWeave when standard completion has no matches'
        Script = {
            $action = Invoke-PrivatePathWeave 'Get-PathWeaveTabAction' @('nvim inbox', 10)
            Assert-Equal $action 'PathWeave' 'Unknown partial path tokens should use PathWeave on Tab.'
        }
    },
    @{
        Name = 'uses CLI results to rewrite the buffer on Tab fallback'
        Script = {
            $workspace = New-TempPathWeaveWorkspace
            try {
                Reset-PathWeaveTabCycleState
                New-Item -ItemType Directory -Path (Join-Path $workspace '00-Inbox') | Out-Null
                New-Item -ItemType File -Path (Join-Path $workspace 'my-inbox.md') | Out-Null

                Set-PathWeaveConfig -Executable 'pwv'
                $result = Invoke-PrivatePathWeave 'Invoke-PathWeaveTabCompletionForBuffer' @('nvim inbox', 10, $workspace, 'First')

                Assert-Equal $result.Action 'PathWeave' 'Tab fallback should switch to PathWeave when no standard completion exists.'
                Assert-Equal $result.Line 'nvim .\00-Inbox\' 'The best CLI result should be inserted into the buffer.'
                Assert-True ($result.ResultCount -ge 1) 'PathWeave search should return at least one result.'
            }
            finally {
                Reset-PathWeaveTabCycleState
                Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = 'Tab fallback preserves later arguments and returns targeted replacement'
        Script = {
            $workspace = New-TempPathWeaveWorkspace
            try {
                Reset-PathWeaveTabCycleState
                New-Item -ItemType Directory -Path (Join-Path $workspace '00-Inbox') | Out-Null

                Set-PathWeaveConfig -Executable 'pwv'
                $result = Invoke-PrivatePathWeave 'Invoke-PathWeaveTabCompletionForBuffer' @('Copy-Item inbox .\backup\', 15, $workspace, 'First')

                Assert-Equal $result.Action 'PathWeave' 'Tab fallback should use PathWeave for the active argument.'
                Assert-Equal $result.Line 'Copy-Item .\00-Inbox\ .\backup\' 'Later arguments should remain in place.'
                Assert-Equal $result.Cursor 21 'Cursor should land after the inserted candidate, before later arguments.'
                Assert-Equal $result.ReplaceStart 10 'Targeted replacement should start at the active token.'
                Assert-Equal $result.ReplaceLength 5 'Targeted replacement should replace only the active token.'
            }
            finally {
                Reset-PathWeaveTabCycleState
                Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = 'cycles through PathWeave matches on repeated Tab'
        Script = {
            $workspace = New-TempPathWeaveWorkspace
            try {
                Reset-PathWeaveTabCycleState
                New-Item -ItemType Directory -Path (Join-Path $workspace '00-Inbox') | Out-Null
                New-Item -ItemType File -Path (Join-Path $workspace 'my-inbox.md') | Out-Null

                Set-PathWeaveConfig -Executable 'pwv'
                $first = Invoke-PrivatePathWeave 'Invoke-PathWeaveTabCompletionForBuffer' @('nvim inbox', 10, $workspace, 'First')
                $second = Invoke-PrivatePathWeave 'Invoke-PathWeaveTabCompletionForBuffer' @($first.Line, $first.Cursor, $workspace, 'First')
                $third = Invoke-PrivatePathWeave 'Invoke-PathWeaveTabCompletionForBuffer' @($second.Line, $second.Cursor, $workspace, 'First')

                Assert-Equal $first.Line 'nvim .\00-Inbox\' 'First Tab should insert the top-ranked candidate.'
                Assert-Equal $second.Line 'nvim .\my-inbox.md' 'Second Tab should advance to the next candidate.'
                Assert-Equal $third.Line 'nvim .\00-Inbox\' 'Third Tab should wrap around to the first candidate.'
            }
            finally {
                Reset-PathWeaveTabCycleState
                Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = 'cycles backward through PathWeave matches on Shift+Tab'
        Script = {
            $workspace = New-TempPathWeaveWorkspace
            try {
                Reset-PathWeaveTabCycleState
                New-Item -ItemType Directory -Path (Join-Path $workspace '00-Inbox') | Out-Null
                New-Item -ItemType File -Path (Join-Path $workspace 'my-inbox.md') | Out-Null

                Set-PathWeaveConfig -Executable 'pwv'
                $first = Invoke-PrivatePathWeave 'Invoke-PathWeaveTabCompletionForBuffer' @('nvim inbox', 10, $workspace, 'First', 1)
                $backward = Invoke-PrivatePathWeave 'Invoke-PathWeaveTabCompletionForBuffer' @($first.Line, $first.Cursor, $workspace, 'First', -1)

                Assert-Equal $first.Line 'nvim .\00-Inbox\' 'Forward Tab should still choose the first candidate initially.'
                Assert-Equal $backward.Line 'nvim .\my-inbox.md' 'Shift+Tab should move to the previous candidate and wrap backward.'
            }
            finally {
                Reset-PathWeaveTabCycleState
                Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = 'starts reverse cycle from the last candidate'
        Script = {
            $workspace = New-TempPathWeaveWorkspace
            try {
                Reset-PathWeaveTabCycleState
                New-Item -ItemType Directory -Path (Join-Path $workspace '00-Inbox') | Out-Null
                New-Item -ItemType File -Path (Join-Path $workspace 'my-inbox.md') | Out-Null

                Set-PathWeaveConfig -Executable 'pwv'
                $result = Invoke-PrivatePathWeave 'Invoke-PathWeaveTabCompletionForBuffer' @('nvim inbox', 10, $workspace, 'First', -1)

                Assert-Equal $result.Line 'nvim .\my-inbox.md' 'Initial Shift+Tab should start from the last candidate.'
            }
            finally {
                Reset-PathWeaveTabCycleState
                Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = 'keeps standard action for command-name completion on Tab'
        Script = {
            $workspace = New-TempPathWeaveWorkspace
            try {
                Reset-PathWeaveTabCycleState
                $result = Invoke-PrivatePathWeave 'Invoke-PathWeaveTabCompletionForBuffer' @('Get-ChildIte', 12, $workspace, 'First')
                Assert-Equal $result.Action 'Standard' 'Command-name completion should remain with standard Tab behavior.'
                Assert-Equal $result.Line 'Get-ChildIte' 'Standard fallback simulation should not rewrite the buffer.'
            }
            finally {
                Reset-PathWeaveTabCycleState
                Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
)

$passed = 0
foreach ($test in $tests) {
    try {
        & $test.Script
        Write-Host "PASS $($test.Name)"
        $passed++
    }
    catch {
        Write-Error "FAIL $($test.Name)`n$($_.Exception.Message)"
        exit 1
    }
}

Write-Host "PASS $passed/$($tests.Count) tests"
