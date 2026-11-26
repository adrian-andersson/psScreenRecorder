[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    foreach($dependency in @('Read-FFmpegProgress.ps1'))
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Update-ScreenRecordingState'
    . $fileName

    function New-TestRecording
    {
        param([bool]$HasExited = $false, [string]$State = 'Recording')
        [PSCustomObject]@{
            State = $State
            ProgressPath = 'unused'
            Frames = $null; DroppedFrames = $null; DuplicatedFrames = $null; Elapsed = $null; Size = $null; Speed = $null
            Handle = [PSCustomObject]@{ Process = [PSCustomObject]@{ HasExited = $HasExited } }
        }
    }
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Update-ScreenRecordingState' {
    It 'Copies the latest progress onto the recording' {
        Mock Read-FFmpegProgress { [PSCustomObject]@{ Frame = 300; DroppedFrames = 3; DuplicatedFrames = 1; Elapsed = [timespan]::FromSeconds(10); Size = 999; Speed = 1.0 } }
        $recording = Update-ScreenRecordingState -Recording (New-TestRecording)
        $recording.Frames | Should -Be 300
        $recording.DroppedFrames | Should -Be 3
        $recording.Elapsed | Should -Be ([timespan]::FromSeconds(10))
        $recording.Size | Should -Be 999
    }

    It 'Leaves the figures alone when there is no progress yet' {
        Mock Read-FFmpegProgress {}
        (Update-ScreenRecordingState -Recording (New-TestRecording)).Frames | Should -BeNullOrEmpty
    }

    It 'Marks a recording Ended when ffmpeg exited by itself' {
        Mock Read-FFmpegProgress {}
        (Update-ScreenRecordingState -Recording (New-TestRecording -HasExited $true)).State | Should -Be 'Ended'
    }

    It 'Does not change a saved recording' {
        Mock Read-FFmpegProgress {}
        (Update-ScreenRecordingState -Recording (New-TestRecording -HasExited $true -State 'Saved')).State | Should -Be 'Saved'
    }
}
