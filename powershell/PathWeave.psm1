$script:PathWeaveConfig = @{
    Executable = 'pwv'
    MaxResults = 30
    MaxDepth = 4
    IncludeHidden = $false
    FollowLinks = $false
    EnableTabIntegration = $false
}

$script:PathWeaveTabState = $null

function Get-PathWeaveConfig {
    [pscustomobject]$script:PathWeaveConfig
}

function Set-PathWeaveConfig {
    param(
        [string]$Executable,
        [int]$MaxResults,
        [int]$MaxDepth,
        [bool]$IncludeHidden,
        [bool]$FollowLinks,
        [bool]$EnableTabIntegration
    )

    if ($PSBoundParameters.ContainsKey('Executable')) { $script:PathWeaveConfig.Executable = $Executable }
    if ($PSBoundParameters.ContainsKey('MaxResults')) { $script:PathWeaveConfig.MaxResults = $MaxResults }
    if ($PSBoundParameters.ContainsKey('MaxDepth')) { $script:PathWeaveConfig.MaxDepth = $MaxDepth }
    if ($PSBoundParameters.ContainsKey('IncludeHidden')) { $script:PathWeaveConfig.IncludeHidden = $IncludeHidden }
    if ($PSBoundParameters.ContainsKey('FollowLinks')) { $script:PathWeaveConfig.FollowLinks = $FollowLinks }
    if ($PSBoundParameters.ContainsKey('EnableTabIntegration')) { $script:PathWeaveConfig.EnableTabIntegration = $EnableTabIntegration }
}

function Enable-PathWeave {
    param(
        [switch]$UseTab
    )

    if (-not (Get-Module -ListAvailable -Name PSReadLine)) {
        throw 'PSReadLine is required for PathWeave.'
    }

    Set-PSReadLineKeyHandler -Chord Ctrl+Spacebar -BriefDescription 'PathWeave completion' -ScriptBlock {
        Invoke-PathWeaveCompletion
    }

    if ($UseTab -or $script:PathWeaveConfig.EnableTabIntegration) {
        Set-PSReadLineKeyHandler -Chord Tab -BriefDescription 'PathWeave smart completion' -ScriptBlock {
            Invoke-PathWeaveTabCompletion
        }
        Set-PSReadLineKeyHandler -Chord Shift+Tab -BriefDescription 'PathWeave reverse completion' -ScriptBlock {
            Invoke-PathWeaveReverseTabCompletion
        }
    }
}

function Disable-PathWeave {
    if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
        Set-PSReadLineKeyHandler -Chord Ctrl+Spacebar -Function SelfInsert
        Set-PSReadLineKeyHandler -Chord Tab -Function Complete
        Set-PSReadLineKeyHandler -Chord Shift+Tab -Function TabCompletePrevious
    }
}

function Invoke-PathWeaveCompletion {
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $state = Get-PathWeaveTokenStateFromBuffer -Line $line -Cursor $cursor
    if (-not $state.Query) {
        return
    }

    $results = Invoke-PathWeaveSearch -Query $state.Query
    if (-not $results -or $results.Count -eq 0) {
        return
    }

    $selected = if ($results.Count -eq 1) {
        $results[0]
    }
    else {
        Select-PathWeaveResult -Results $results
    }

    if (-not $selected) {
        return
    }

    $replacement = Get-PathWeaveReplacementText -SelectedItem $selected
    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($state.Start, $state.Length, $replacement)
    return $true
}

function Invoke-PathWeaveTabCompletion {
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    $result = Invoke-PathWeaveTabCompletionForBuffer -Line $line -Cursor $cursor -Direction 1
    if ($result.Action -eq 'Standard') {
        Clear-PathWeaveTabState
        [Microsoft.PowerShell.PSConsoleReadLine]::Complete()
        return
    }

    if ($result.Action -eq 'PathWeave') {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($result.ReplaceStart, $result.ReplaceLength, $result.Replacement)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($result.Cursor)
        return
    }

    $usedPathWeave = Invoke-PathWeaveCompletion
    if (-not $usedPathWeave) {
        Clear-PathWeaveTabState
        [Microsoft.PowerShell.PSConsoleReadLine]::Complete()
    }
}

function Invoke-PathWeaveReverseTabCompletion {
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    $result = Invoke-PathWeaveTabCompletionForBuffer -Line $line -Cursor $cursor -Direction -1
    if ($result.Action -eq 'Standard') {
        Clear-PathWeaveTabState
        [Microsoft.PowerShell.PSConsoleReadLine]::TabCompletePrevious()
        return
    }

    if ($result.Action -eq 'PathWeave') {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($result.ReplaceStart, $result.ReplaceLength, $result.Replacement)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($result.Cursor)
        return
    }

    $usedPathWeave = Invoke-PathWeaveCompletion
    if (-not $usedPathWeave) {
        Clear-PathWeaveTabState
        [Microsoft.PowerShell.PSConsoleReadLine]::TabCompletePrevious()
    }
}

function Invoke-PathWeaveTabCompletionForBuffer {
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [Parameter(Mandatory)]
        [int]$Cursor,
        [string]$Cwd = (Get-Location).Path,
        [ValidateSet('First', 'RequireSingle')]
        [string]$SelectionMode = 'First',
        [ValidateSet(-1, 1)]
        [int]$Direction = 1
    )

    if (Test-PathWeaveTabStateMatchesBuffer -Line $Line -Cursor $Cursor) {
        return Get-NextPathWeaveTabCycleResult -Direction $Direction
    }

    $action = Get-PathWeaveTabAction -Line $Line -Cursor $Cursor
    if ($action -eq 'Standard') {
        Clear-PathWeaveTabState
        return [pscustomobject]@{
            Action = 'Standard'
            Line = $Line
            Cursor = $Cursor
        }
    }

    $state = Get-PathWeaveTokenStateFromBuffer -Line $Line -Cursor $Cursor
    $results = @(Invoke-PathWeaveSearch -Query $state.Query -Cwd $Cwd)
    if (-not $results -or $results.Count -eq 0) {
        Clear-PathWeaveTabState
        return [pscustomobject]@{
            Action = 'Standard'
            Line = $Line
            Cursor = $Cursor
        }
    }

    if ($SelectionMode -eq 'RequireSingle' -and $results.Count -ne 1) {
        Clear-PathWeaveTabState
        return [pscustomobject]@{
            Action = 'Menu'
            Line = $Line
            Cursor = $Cursor
            Results = $results
        }
    }

    $selectedIndex = if ($Direction -ge 0) { 0 } else { $results.Count - 1 }
    $selected = $results[$selectedIndex]
    $applied = Apply-PathWeaveCompletionToBuffer -Line $Line -Cursor $Cursor -SelectedItem $selected
    Set-PathWeaveTabState `
        -OriginalLine $Line `
        -OriginalCursor $Cursor `
        -Results $results `
        -Index $selectedIndex `
        -CurrentLine $applied.Line `
        -CurrentCursor $applied.Cursor `
        -CurrentStart $applied.Start `
        -CurrentLength $applied.Replacement.Length

    [pscustomobject]@{
        Action = 'PathWeave'
        Line = $applied.Line
        Cursor = $applied.Cursor
        Replacement = $applied.Replacement
        ReplaceStart = $applied.Start
        ReplaceLength = $applied.Length
        ResultCount = $results.Count
        SelectedPath = $selected.path
    }
}

function Set-PathWeaveTabState {
    param(
        [Parameter(Mandatory)]
        [string]$OriginalLine,
        [Parameter(Mandatory)]
        [int]$OriginalCursor,
        [Parameter(Mandatory)]
        [object[]]$Results,
        [Parameter(Mandatory)]
        [int]$Index,
        [Parameter(Mandatory)]
        [string]$CurrentLine,
        [Parameter(Mandatory)]
        [int]$CurrentCursor,
        [Parameter(Mandatory)]
        [int]$CurrentStart,
        [Parameter(Mandatory)]
        [int]$CurrentLength
    )

    $script:PathWeaveTabState = [pscustomobject]@{
        OriginalLine = $OriginalLine
        OriginalCursor = $OriginalCursor
        Results = $Results
        Index = $Index
        CurrentLine = $CurrentLine
        CurrentCursor = $CurrentCursor
        CurrentStart = $CurrentStart
        CurrentLength = $CurrentLength
    }
}

function Clear-PathWeaveTabState {
    $script:PathWeaveTabState = $null
}

function Test-PathWeaveTabStateMatchesBuffer {
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [Parameter(Mandatory)]
        [int]$Cursor
    )

    if (-not $script:PathWeaveTabState) {
        return $false
    }

    return $script:PathWeaveTabState.CurrentLine -eq $Line -and $script:PathWeaveTabState.CurrentCursor -eq $Cursor
}

function Get-NextPathWeaveTabCycleResult {
    param(
        [ValidateSet(-1, 1)]
        [int]$Direction = 1
    )

    if (-not $script:PathWeaveTabState -or -not $script:PathWeaveTabState.Results -or $script:PathWeaveTabState.Results.Count -eq 0) {
        return [pscustomobject]@{
            Action = 'Standard'
        }
    }

    $count = $script:PathWeaveTabState.Results.Count
    $nextIndex = ($script:PathWeaveTabState.Index + $Direction + $count) % $count
    $selected = $script:PathWeaveTabState.Results[$nextIndex]
    $applied = Apply-PathWeaveCompletionToBuffer -Line $script:PathWeaveTabState.OriginalLine -Cursor $script:PathWeaveTabState.OriginalCursor -SelectedItem $selected
    $replaceStart = $script:PathWeaveTabState.CurrentStart
    $replaceLength = $script:PathWeaveTabState.CurrentLength

    Set-PathWeaveTabState `
        -OriginalLine $script:PathWeaveTabState.OriginalLine `
        -OriginalCursor $script:PathWeaveTabState.OriginalCursor `
        -Results $script:PathWeaveTabState.Results `
        -Index $nextIndex `
        -CurrentLine $applied.Line `
        -CurrentCursor $applied.Cursor `
        -CurrentStart $applied.Start `
        -CurrentLength $applied.Replacement.Length

    [pscustomobject]@{
        Action = 'PathWeave'
        Line = $applied.Line
        Cursor = $applied.Cursor
        Replacement = $applied.Replacement
        ReplaceStart = $replaceStart
        ReplaceLength = $replaceLength
        ResultCount = $script:PathWeaveTabState.Results.Count
        SelectedPath = $selected.path
    }
}

function Select-PathWeaveResult {
    param(
        [Parameter(Mandatory)]
        [object[]]$Results
    )

    if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
        return $Results | ForEach-Object {
            [pscustomobject]@{
                Label = (Format-PathWeaveChoiceText -Result $_)
                Item = $_
            }
        } | Out-GridView -Title 'PathWeave Completion' -OutputMode Single | Select-Object -ExpandProperty Item
    }

    $choices = [System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]]::new()
    for ($index = 0; $index -lt $Results.Count; $index++) {
        $result = $Results[$index]
        $label = Format-PathWeaveChoiceLabel -Result $result -Index $index
        $help = Format-PathWeaveChoiceHelp -Result $result
        $choices.Add([System.Management.Automation.Host.ChoiceDescription]::new($label, $help))
    }

    $selection = $host.UI.PromptForChoice('PathWeave Completion', 'Select a path', $choices, 0)
    if ($selection -lt 0) {
        return $null
    }

    return $Results[$selection]
}

function Format-PathWeaveChoiceText {
    param(
        [Parameter(Mandatory)]
        [psobject]$Result
    )

    "[{0}] {1}" -f $Result.kind, $Result.display
}

function Format-PathWeaveChoiceLabel {
    param(
        [Parameter(Mandatory)]
        [psobject]$Result,
        [Parameter(Mandatory)]
        [int]$Index
    )

    $hotkey = if ($Index -lt 9) { [string]($Index + 1) } else { [char](65 + ($Index - 9)) }
    "&{0} {1}" -f $hotkey, (Format-PathWeaveChoiceText -Result $Result)
}

function Format-PathWeaveChoiceHelp {
    param(
        [Parameter(Mandatory)]
        [psobject]$Result
    )

    "Insert {0}" -f $Result.path
}

function Invoke-PathWeaveSearch {
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [string]$Cwd = (Get-Location).Path
    )

    $executable = Resolve-PathWeaveExecutable -ConfiguredExecutable $script:PathWeaveConfig.Executable
    $command = @(
        $executable
        'search'
        '--query'
        $Query
        '--cwd'
        $Cwd
        '--max-results'
        $script:PathWeaveConfig.MaxResults
        '--max-depth'
        $script:PathWeaveConfig.MaxDepth
        '--format'
        'json'
    )

    if ($script:PathWeaveConfig.IncludeHidden) {
        $command += '--hidden'
    }

    if ($script:PathWeaveConfig.FollowLinks) {
        $command += '--follow-links'
    }

    try {
        $json = & $command[0] $command[1..($command.Count - 1)] 2>&1
    }
    catch {
        throw "Failed to run PathWeave executable '$executable': $_"
    }

    if ($LASTEXITCODE -ne 0) {
        throw "PathWeave search failed: $json"
    }

    return $json | ConvertFrom-Json
}

function Resolve-PathWeaveExecutable {
    param(
        [Parameter(Mandatory)]
        [string]$ConfiguredExecutable
    )

    $command = Get-Command $ConfiguredExecutable -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $candidates = @(
        (Join-Path $moduleRoot 'pwv.exe')
        (Join-Path $moduleRoot 'pwv')
        (Join-Path $moduleRoot 'bin/pwv.exe')
        (Join-Path $moduleRoot 'bin/pwv')
        (Join-Path $moduleRoot 'target/release/pwv.exe')
        (Join-Path $moduleRoot 'target/release/pwv')
        (Join-Path $moduleRoot 'target/debug/pwv.exe')
        (Join-Path $moduleRoot 'target/debug/pwv')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "PathWeave executable '$ConfiguredExecutable' was not found on PATH or under the local target directory."
}

function Get-PathWeaveTabAction {
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [Parameter(Mandatory)]
        [int]$Cursor
    )

    if (Test-PathWeaveHasStandardCompletions -Line $Line -Cursor $Cursor) {
        return 'Standard'
    }

    $state = Get-PathWeaveTokenStateFromBuffer -Line $Line -Cursor $Cursor
    if ($state.Query) {
        return 'PathWeave'
    }

    'Standard'
}

function Test-PathWeaveHasStandardCompletions {
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [Parameter(Mandatory)]
        [int]$Cursor
    )

    try {
        $completion = [System.Management.Automation.CommandCompletion]::CompleteInput($Line, $Cursor, $null)
    }
    catch {
        return $false
    }

    return $completion -and $completion.CompletionMatches.Count -gt 0
}

function Get-PathWeaveTokenState {
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    Get-PathWeaveTokenStateFromBuffer -Line $line -Cursor $cursor
}

function Get-PathWeaveTokenStateFromBuffer {
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [Parameter(Mandatory)]
        [int]$Cursor
    )

    $ast = $null
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$errors)

    foreach ($token in $tokens) {
        if ($Cursor -ge $token.Extent.StartOffset -and $Cursor -le $token.Extent.EndOffset) {
            return [pscustomobject]@{
                Query = $Line.Substring($token.Extent.StartOffset, $Cursor - $token.Extent.StartOffset).Trim("'`"")
                Start = $token.Extent.StartOffset
                Length = $token.Extent.EndOffset - $token.Extent.StartOffset
            }
        }
    }

    $start = $Cursor
    while ($start -gt 0 -and -not [char]::IsWhiteSpace($Line[$start - 1])) {
        $start--
    }

    [pscustomobject]@{
        Query = $Line.Substring($start, $Cursor - $start).Trim("'`"")
        Start = $start
        Length = $Cursor - $start
    }
}

function Get-PathWeaveReplacementText {
    param(
        [Parameter(Mandatory)]
        [psobject]$SelectedItem
    )

    ConvertTo-PathWeaveInsertionText -Path $SelectedItem.path -Kind $SelectedItem.kind
}

function Apply-PathWeaveCompletionToBuffer {
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [Parameter(Mandatory)]
        [int]$Cursor,
        [Parameter(Mandatory)]
        [psobject]$SelectedItem
    )

    $state = Get-PathWeaveTokenStateFromBuffer -Line $Line -Cursor $Cursor
    $replacement = Get-PathWeaveReplacementText -SelectedItem $SelectedItem
    $newLine = $Line.Remove($state.Start, $state.Length).Insert($state.Start, $replacement)

    [pscustomobject]@{
        Line = $newLine
        Cursor = $state.Start + $replacement.Length
        Start = $state.Start
        Length = $state.Length
        Replacement = $replacement
        Query = $state.Query
    }
}

function ConvertTo-PathWeaveInsertionText {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Kind
    )

    $value = $Path
    if ($Kind -eq 'directory' -and -not $value.EndsWith('\')) {
        $value = "$value\"
    }

    if ($value.Contains("'")) {
        $value = $value -replace "'", "''"
    }

    if ($value -match '\s') {
        return "'$value'"
    }

    return $value
}
