[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

#A real repair of a killed recording runs in tests/Recording.Integration.Tests.ps1
BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'Invoke-FFmpeg.ps1'
        'Get-VideoMetadata.ps1'
        'Convert-RecordingContainer.ps1'
        'Add-VideoMetadataMember.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Repair-ScreenRecording'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Repair-ScreenRecording' {
    BeforeEach {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $folder
        $leftBehind = Join-Path -Path $folder -ChildPath 'Screen Recording 2026-11-27 14-05-09.recording.mkv'
        Set-Content -LiteralPath $leftBehind -Value 'pretend matroska'
        Mock Convert-RecordingContainer { Set-Content -LiteralPath $Destination -Value 'pretend mp4' }
        Mock Get-VideoMetadata { [PSCustomObject]@{ Duration = [timespan]::FromSeconds(9); Width = 800; Height = 600; FrameRate = 30; VideoCodec = 'h264' } }
    }

    It 'Saves as the name the recording would have had, as .mp4, and removes the left-behind file' {
        $file = Repair-ScreenRecording -Path $leftBehind
        $file.Name | Should -Be 'Screen Recording 2026-11-27 14-05-09.mp4'
        $file.Duration | Should -Be ([timespan]::FromSeconds(9))
        $leftBehind | Should -Not -Exist
    }

    It 'Keeps the original with -KeepSource' {
        $null = Repair-ScreenRecording -Path $leftBehind -KeepSource
        $leftBehind | Should -Exist
    }

    It 'Saves to -Destination, in its container' {
        $destination = Join-Path -Path $folder -ChildPath 'fixed.mkv'
        (Repair-ScreenRecording -Path $leftBehind -Destination $destination).FullName | Should -Be $destination
    }

    It 'Passes the codec it read on, so HEVC is tagged for Apple players' {
        Mock Get-VideoMetadata { [PSCustomObject]@{ VideoCodec = 'hevc' } }
        $null = Repair-ScreenRecording -Path $leftBehind
        Should -Invoke Convert-RecordingContainer -ParameterFilter { $Codec -eq 'hevc' }
    }

    It 'Takes left-behind files from the pipeline, such as Get-ChildItem' {
        $second = Join-Path -Path $folder -ChildPath 'other.recording.mkv'
        Set-Content -LiteralPath $second -Value 'pretend matroska'
        @(Get-ChildItem -LiteralPath $folder -Filter '*.recording.mkv' | Repair-ScreenRecording).Count | Should -Be 2
    }

    It 'Writes an error for <Case>' -ForEach @(
        @{ Case = 'a missing file'; Setup = { Remove-Item -LiteralPath $leftBehind }; Message = '*not found*' }
        @{ Case = 'an empty file'; Setup = { Set-Content -LiteralPath $leftBehind -Value '' -NoNewline }; Message = '*empty*' }
        @{ Case = 'an existing destination'; Setup = { Set-Content -LiteralPath ($leftBehind -replace '\.recording\.mkv$','.mp4') -Value 'x' }; Message = '*already exists*' }
        @{ Case = 'a file that isn''t video'; Setup = { Mock Get-VideoMetadata { throw 'Invalid data found' } }; Message = '*can''t be read as a video*' }
        @{ Case = 'a failed remux'; Setup = { Mock Convert-RecordingContainer { throw 'muxer error' } }; Message = '*Unable to repair*muxer error*' }
    ) {
        & $Setup
        Repair-ScreenRecording -Path $leftBehind -ErrorVariable problems -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        $problems.Where{ $_.ToString() -like $Message }.Count | Should -Be 1
    }

    It 'Writes an error for an unsupported container, or the source itself as the destination' {
        Repair-ScreenRecording -Path $leftBehind -Destination (Join-Path -Path $folder -ChildPath 'x.avi') -ErrorVariable problems -ErrorAction SilentlyContinue
        $problems[0].ToString() | Should -BeLike "*not '.avi'*"
        Repair-ScreenRecording -Path $leftBehind -Destination $leftBehind -ErrorVariable problems -ErrorAction SilentlyContinue
        $problems[0].ToString() | Should -BeLike '*same file*'
    }

    It 'Does nothing with -WhatIf' {
        Repair-ScreenRecording -Path $leftBehind -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Convert-RecordingContainer -Times 0 -Exactly
    }
}

Describe 'Convert-RecordingContainer' {
    BeforeEach {
        Mock Invoke-FFmpeg { [PSCustomObject]@{ ExitCode = 0; StandardOutput = @(); StandardError = @() } }
    }

    It 'Copies the video without re-encoding, dropping a corrupt end, with faststart for <Extension>' -ForEach @(
        @{ Extension = '.mp4' }
        @{ Extension = '.mov' }
    ) {
        Convert-RecordingContainer -Path 'in.mkv' -Destination "out$Extension"
        Should -Invoke Invoke-FFmpeg -ParameterFilter {
            $joined = $ArgumentList -join ' '
            $joined -like '*-fflags +discardcorrupt -i in.mkv -map 0 -c copy -movflags +faststart*' -and $ArgumentList[-1] -eq "out$Extension"
        }
    }

    It 'Leaves faststart and tags out of Matroska' {
        Convert-RecordingContainer -Path 'in.mkv' -Destination 'out.mkv' -Codec HEVC
        Should -Invoke Invoke-FFmpeg -ParameterFilter { $ArgumentList -notcontains '-movflags' -and $ArgumentList -notcontains '-tag:v' }
    }

    It 'Tags HEVC as hvc1 in MP4' {
        Convert-RecordingContainer -Path 'in.mkv' -Destination 'out.mp4' -Codec hevc
        Should -Invoke Invoke-FFmpeg -ParameterFilter { ($ArgumentList -join ' ') -like '*-tag:v hvc1*' }
    }
}

Describe 'Add-VideoMetadataMember' {
    BeforeAll {
        $video = Join-Path -Path $TestDrive -ChildPath 'video.mp4'
        Set-Content -LiteralPath $video -Value 'pretend'
    }

    It 'Adds duration, size, frame rate and codec, and keeps it a file' {
        Mock Get-VideoMetadata { [PSCustomObject]@{ Duration = [timespan]::FromSeconds(2); Width = 10; Height = 20; FrameRate = 25; VideoCodec = 'av1' } }
        $file = Get-Item -LiteralPath $video | Add-VideoMetadataMember
        $file | Should -BeOfType [System.IO.FileInfo]
        $file.VideoCodec | Should -Be 'av1'
        $file.Height | Should -Be 20
    }

    It 'Returns the file unchanged when it can''t be read' {
        Mock Get-VideoMetadata { throw 'no ffprobe' }
        $file = Get-Item -LiteralPath $video | Add-VideoMetadataMember
        $file.Name | Should -Be 'video.mp4'
        $file.PSObject.Properties['VideoCodec'] | Should -BeNullOrEmpty
    }
}
