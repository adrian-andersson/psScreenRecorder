[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    foreach($dependency in @('New-CaptureTarget.ps1','Get-CaptureTarget.ps1'))
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Get-CaptureTargetCompletion'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Get-CaptureTargetCompletion' {
    BeforeEach {
        Mock Get-CaptureTarget -ParameterFilter { !$Window } {
            New-CaptureTarget -Kind Monitor -Index 0 -Name 'DISPLAY1' -X 0 -Y 0 -Width 3440 -Height 1440 -IsPrimary $true
            New-CaptureTarget -Kind Monitor -Index 1 -Name 'DISPLAY2' -X 3440 -Y 0 -Width 1920 -Height 1080
        }
        Mock Get-CaptureTarget -ParameterFilter { $Window } {
            New-CaptureTarget -Kind Window -Title 'notes.md [Preview] - Visual Studio Code' -ProcessName 'Code'
            New-CaptureTarget -Kind Window -Title "Adrian's page - Edge" -ProcessName 'msedge'
            New-CaptureTarget -Kind Window -Title 'notes.md [Preview] - Visual Studio Code' -ProcessName 'Code'
        }
    }

    Context 'Monitors' {
        It 'Offers each monitor''s number, describing it' {
            $completions = @(Get-CaptureTargetCompletion -Kind Monitor)
            $completions.CompletionText | Should -Be @('0','1')
            $completions[0].ToolTip | Should -Be '0: DISPLAY1 3440x1440 (primary)'
        }

        It 'Narrows to what''s been typed' {
            (Get-CaptureTargetCompletion -Kind Monitor -WordToComplete '1').CompletionText | Should -Be '1'
        }
    }

    Context 'Windows' {
        It 'Offers each title once, quoted, with wildcard characters escaped so it matches itself' {
            $completions = @(Get-CaptureTargetCompletion -Kind Window)
            $completions.Count | Should -Be 2
            $completions[0].CompletionText | Should -Be "'notes.md ``[Preview``] - Visual Studio Code'"
            $completions[0].ToolTip | Should -BeLike '*(Code)'
            #The escaped title really does match the window it came from
            'notes.md [Preview] - Visual Studio Code' -like ($completions[0].CompletionText.Trim("'")) | Should -BeTrue
        }

        It 'Doubles single quotes inside titles' {
            (Get-CaptureTargetCompletion -Kind Window -WordToComplete 'Edge').CompletionText | Should -Be "'Adrian''s page - Edge'"
        }

        It 'Matches what''s typed anywhere in the title, or at the start of the process name' {
            (Get-CaptureTargetCompletion -Kind Window -WordToComplete 'Visual').ListItemText | Should -BeLike 'notes.md*'
            (Get-CaptureTargetCompletion -Kind Window -WordToComplete 'msed').ListItemText | Should -BeLike 'Adrian*'
            (Get-CaptureTargetCompletion -Kind Window -WordToComplete "'Edge").ListItemText | Should -BeLike 'Adrian*'
        }

        It 'Returns nothing, rather than an error, when windows can''t be listed' {
            Mock Get-CaptureTarget -ParameterFilter { $Window } { throw 'only supported on Windows' }
            Get-CaptureTargetCompletion -Kind Window | Should -BeNullOrEmpty
        }
    }
}
