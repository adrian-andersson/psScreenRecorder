[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    foreach($dependency in @('Invoke-FFmpeg.ps1'))
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Get-VideoMetadata'
    . $fileName

    #Shaped like real ffprobe -print_format json output, with cover art and an audio stream to skip past
    $probeJson = @'
{
    "streams": [
        { "index": 0, "codec_name": "mjpeg", "codec_type": "video", "width": 300, "height": 300, "disposition": { "attached_pic": 1 } },
        { "index": 1, "codec_name": "h264", "codec_type": "video", "width": 1920, "height": 1080, "pix_fmt": "yuv420p",
          "avg_frame_rate": "30000/1001", "r_frame_rate": "30000/1001", "nb_frames": "2997", "disposition": { "attached_pic": 0 } },
        { "index": 2, "codec_name": "aac", "codec_type": "audio" }
    ],
    "format": { "format_name": "mov,mp4,m4a,3gp,3g2,mj2", "duration": "100.100000", "bit_rate": "4500000", "size": "56312500" }
}
'@
    $clip = Join-Path -Path $TestDrive -ChildPath 'my clip.mp4'
    Set-Content -LiteralPath $clip -Value 'pretend video'
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Get-VideoMetadata' {
    BeforeEach {
        Mock Invoke-FFmpeg { [PSCustomObject]@{ ExitCode = 0; StandardOutput = $probeJson -split "`n"; StandardError = @() } }
    }

    Context 'Reading ffprobe output' {
        It 'Reports the main video stream, skipping cover art' {
            $result = Get-VideoMetadata -Path $clip
            $result.Width | Should -Be 1920
            $result.Height | Should -Be 1080
            $result.VideoCodec | Should -Be 'h264'
            $result.PixelFormat | Should -Be 'yuv420p'
        }

        It 'Turns the frame rate fraction into a number' {
            (Get-VideoMetadata -Path $clip).FrameRate | Should -Be 29.97
        }

        It 'Reads the duration as a TimeSpan, whatever the current culture' {
            $savedCulture = [cultureinfo]::CurrentCulture
            try{
                #German uses a comma for decimals, which would misread 100.100000
                [cultureinfo]::CurrentCulture = [cultureinfo]::GetCultureInfo('de-DE')
                (Get-VideoMetadata -Path $clip).Duration | Should -Be ([timespan]::FromSeconds(100.1))
            }finally{
                [cultureinfo]::CurrentCulture = $savedCulture
            }
        }

        It 'Reports the file details, container, bitrate and audio' {
            $result = Get-VideoMetadata -Path $clip
            $result.Name | Should -Be 'my clip.mp4'
            $result.Path | Should -Be (Get-Item -LiteralPath $clip).FullName
            $result.Container | Should -Be 'mov,mp4,m4a,3gp,3g2,mj2'
            $result.BitRate | Should -Be 4500000
            $result.Size | Should -Be (Get-Item -LiteralPath $clip).Length
            $result.HasAudio | Should -BeTrue
            $result.FrameCount | Should -Be 2997
            $result.Streams.Count | Should -Be 3
            $result.PSTypeNames | Should -Contain 'psScreenRecorder.VideoMetadata'
        }

        It 'Falls back to r_frame_rate when avg_frame_rate is unknown' {
            Mock Invoke-FFmpeg {
                $json = '{"streams":[{"codec_type":"video","width":10,"height":10,"avg_frame_rate":"0/0","r_frame_rate":"25/1"}],"format":{"duration":"1.0"}}'
                [PSCustomObject]@{ ExitCode = 0; StandardOutput = @($json); StandardError = @() }
            }
            (Get-VideoMetadata -Path $clip).FrameRate | Should -Be 25
        }

        It 'Leaves values empty that ffprobe does not report' {
            Mock Invoke-FFmpeg {
                [PSCustomObject]@{ ExitCode = 0; StandardOutput = @('{"streams":[{"codec_type":"video","avg_frame_rate":"0/0","r_frame_rate":"0/0"}],"format":{}}'); StandardError = @() }
            }
            $result = Get-VideoMetadata -Path $clip
            $result.FrameRate | Should -BeNullOrEmpty
            $result.Duration | Should -BeNullOrEmpty
            $result.FrameCount | Should -BeNullOrEmpty
            $result.HasAudio | Should -BeFalse
        }
    }

    Context 'Running ffprobe' {
        It 'Runs ffprobe with JSON output and the full path last' {
            $null = Get-VideoMetadata -Path $clip
            Should -Invoke Invoke-FFmpeg -ParameterFilter {
                $Tool -eq 'ffprobe' -and ($ArgumentList -join ' ') -like '*-print_format json -show_format -show_streams*' -and $ArgumentList[-1] -eq (Get-Item -LiteralPath $clip).FullName
            }
        }

        It 'Counts frames with -CountFrames, preferring the decoded count' {
            Mock Invoke-FFmpeg {
                [PSCustomObject]@{ ExitCode = 0; StandardOutput = @('{"streams":[{"codec_type":"video","nb_frames":"10","nb_read_frames":"42"}],"format":{}}'); StandardError = @() }
            }
            (Get-VideoMetadata -Path $clip -CountFrames).FrameCount | Should -Be 42
            Should -Invoke Invoke-FFmpeg -ParameterFilter { $ArgumentList -contains '-count_frames' }
        }
    }

    Context 'Input and errors' {
        It 'Takes files from the pipeline, such as from Get-ChildItem' {
            $second = Join-Path -Path $TestDrive -ChildPath 'second.mkv'
            Set-Content -LiteralPath $second -Value 'pretend video'
            $results = Get-Item -LiteralPath $clip,$second | Get-VideoMetadata
            $results.Count | Should -Be 2
        }

        It 'Writes an error for a missing file and carries on with the rest' {
            $results = Get-VideoMetadata -Path (Join-Path -Path $TestDrive -ChildPath 'missing.mp4'),$clip -ErrorVariable problems -ErrorAction SilentlyContinue
            @($results).Count | Should -Be 1
            $problems[0].ToString() | Should -BeLike '*not found*'
        }

        It 'Writes an error for a folder' {
            Get-VideoMetadata -Path $TestDrive -ErrorVariable problems -ErrorAction SilentlyContinue
            $problems.Count | Should -Be 1
        }

        It 'Writes an error when ffprobe fails' {
            Mock Invoke-FFmpeg { throw 'ffprobe exited with code 1: Invalid data found when processing input' }
            Get-VideoMetadata -Path $clip -ErrorVariable problems -ErrorAction SilentlyContinue
            #ErrorVariable also records the exception the function caught, so look for the error it wrote
            $problems.Where{ $_.ToString() -like '*Unable to read*Invalid data*' }.Count | Should -Be 1
        }
    }
}
