[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Get-DefaultRecordingPath'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Get-DefaultRecordingPath' {
    It 'Names the file after the start time, with the extension asked for' {
        $path = Get-DefaultRecordingPath -Extension '.mkv' -StartTime ([datetime]::new(2026,11,27,14,5,9))
        Split-Path -Path $path -Leaf | Should -Be 'Screen Recording 2026-11-27 14-05-09.mkv'
    }

    It 'Saves in the Videos folder, creating it if needed' {
        $videos = [Environment]::GetFolderPath('MyVideos')
        $expectedFolder = $(if($videos){$videos}else{Join-Path -Path $HOME -ChildPath 'Videos'})
        Split-Path -Path (Get-DefaultRecordingPath) -Parent | Should -Be $expectedFolder
        $expectedFolder | Should -Exist
    }

    It 'Defaults to .mp4' {
        Get-DefaultRecordingPath | Should -BeLike '*.mp4'
    }
}
