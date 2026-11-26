[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Register-ScreenRecorderExitHandler'
    . $fileName
    . $fileName.Replace('Register-ScreenRecorderExitHandler','Test-StopKeyPressed')
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Register-ScreenRecorderExitHandler' {
    BeforeEach {
        $script:psScreenRecorderExitSubscriber = $null
        Mock Register-EngineEvent {}
    }

    It 'Registers for PowerShell.Exiting, handing over the recordings list, hidden from Get-Job' {
        $recordings = [System.Collections.Generic.List[object]]::new()
        Register-ScreenRecorderExitHandler -Recordings $recordings
        Should -Invoke Register-EngineEvent -ParameterFilter {
            $SourceIdentifier -eq 'PowerShell.Exiting' -and $SupportEvent -and [object]::ReferenceEquals($MessageData, $recordings) -and $Action
        }
    }

    It 'Registers only once per session' {
        $recordings = [System.Collections.Generic.List[object]]::new()
        Register-ScreenRecorderExitHandler -Recordings $recordings
        Register-ScreenRecorderExitHandler -Recordings $recordings
        Should -Invoke Register-EngineEvent -Times 1 -Exactly
    }
}

Describe 'Test-StopKeyPressed' {
    It 'Returns true or false, without waiting' {
        Test-StopKeyPressed | Should -BeOfType [bool]
    }
}
