[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    foreach($dependency in @('Get-ForegroundWindowHandle.ps1'))
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Wait-WindowFocus'
    . $fileName

    $terminal = 100
    $otherWindow = 200
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Wait-WindowFocus' {
    BeforeEach {
        Mock Start-Sleep {}
        #Each call to the mock returns the next window in the sequence, then stays on the last one
        $script:focusSequence = @()
        $script:focusIndex = 0
        Mock Get-ForegroundWindowHandle {
            $value = $script:focusSequence[[math]::Min($script:focusIndex, $script:focusSequence.Count - 1)]
            $script:focusIndex++
            $value
        }
    }

    It 'Waits until another window has focus' {
        $script:focusSequence = @($terminal, $terminal, $terminal, $otherWindow)
        Wait-WindowFocus -WindowHandle $terminal -Until Lost | Should -BeTrue
        Should -Invoke Get-ForegroundWindowHandle -Times 4 -Exactly
    }

    It 'Waits for focus to leave, then come back, so it doesn''t stop straight away' {
        $script:focusSequence = @($terminal, $terminal, $otherWindow, $otherWindow, $terminal)
        Wait-WindowFocus -WindowHandle $terminal -Until Returned | Should -BeTrue
        Should -Invoke Get-ForegroundWindowHandle -Times 5 -Exactly
    }

    It 'Stops waiting, returning false, when the process exits' {
        $script:focusSequence = @($terminal)
        $exitedProcess = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile','-Command','exit' -PassThru -NoNewWindow
        $null = $exitedProcess.WaitForExit(30000)
        Wait-WindowFocus -WindowHandle $terminal -Until Lost -Process $exitedProcess | Should -BeFalse
    }
}
