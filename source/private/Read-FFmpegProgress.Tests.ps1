[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Read-FFmpegProgress'
    . $fileName

    #Two complete blocks, as ffmpeg writes them, then the start of a third
    $progressText = @(
        'frame=30','fps=30.00','drop_frames=0','dup_frames=0','out_time_us=1000000','total_size=48','speed=1.00x','progress=continue'
        'frame=61','fps=29.90','drop_frames=2','dup_frames=1','out_time_us=2033333','total_size=1048576','speed=0.99x','progress=continue'
        'frame=70','fps=29'
    ) -join "`n"
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Read-FFmpegProgress' {
    BeforeEach {
        $progressFile = Join-Path -Path $TestDrive -ChildPath "$([guid]::NewGuid()).progress"
    }

    It 'Reads the last complete block, ignoring one still being written' {
        Set-Content -LiteralPath $progressFile -Value $progressText -NoNewline
        $progress = Read-FFmpegProgress -Path $progressFile
        $progress.Frame | Should -Be 61
        $progress.DroppedFrames | Should -Be 2
        $progress.DuplicatedFrames | Should -Be 1
        $progress.Elapsed | Should -Be ([timespan]::FromTicks(20333330))
        $progress.Size | Should -Be 1048576
        $progress.Fps | Should -Be 29.9
        $progress.Speed | Should -Be 0.99
        $progress.Finished | Should -BeFalse
    }

    It 'Reports when ffmpeg has finished' {
        Set-Content -LiteralPath $progressFile -Value 'frame=5','out_time_us=0','progress=end'
        (Read-FFmpegProgress -Path $progressFile).Finished | Should -BeTrue
    }

    It 'Reads numbers the same whatever the current culture' {
        Set-Content -LiteralPath $progressFile -Value $progressText -NoNewline
        $savedCulture = [cultureinfo]::CurrentCulture
        try{
            [cultureinfo]::CurrentCulture = [cultureinfo]::GetCultureInfo('de-DE')
            (Read-FFmpegProgress -Path $progressFile).Fps | Should -Be 29.9
        }finally{
            [cultureinfo]::CurrentCulture = $savedCulture
        }
    }

    It 'Reads a file another process still has open for writing' {
        $writer = [System.IO.File]::Open($progressFile, 'Create', 'Write', 'Read')
        try{
            $bytes = [System.Text.Encoding]::UTF8.GetBytes("frame=1`nprogress=continue`n")
            $writer.Write($bytes, 0, $bytes.Length)
            $writer.Flush()
            (Read-FFmpegProgress -Path $progressFile).Frame | Should -Be 1
        }finally{
            $writer.Dispose()
        }
    }

    It 'Leaves values empty that ffmpeg reports as N/A' {
        Set-Content -LiteralPath $progressFile -Value 'frame=0','fps=0.00','out_time_us=N/A','total_size=N/A','speed=N/A','progress=continue'
        $progress = Read-FFmpegProgress -Path $progressFile
        $progress.Elapsed | Should -BeNullOrEmpty
        $progress.Size | Should -BeNullOrEmpty
        $progress.Speed | Should -BeNullOrEmpty
    }

    It 'Returns nothing before the first block, or without a file' {
        Set-Content -LiteralPath $progressFile -Value 'frame=1'
        Read-FFmpegProgress -Path $progressFile | Should -BeNullOrEmpty
        Read-FFmpegProgress -Path (Join-Path -Path $TestDrive -ChildPath 'missing.progress') | Should -BeNullOrEmpty
    }
}
