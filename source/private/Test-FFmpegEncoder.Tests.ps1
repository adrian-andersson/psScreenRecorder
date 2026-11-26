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
    $functionName = 'Test-FFmpegEncoder'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Test-FFmpegEncoder' {
    It 'Returns true when the test encode works' {
        Mock Invoke-FFmpeg { [PSCustomObject]@{ ExitCode = 0; StandardOutput = @(); StandardError = @() } }
        Test-FFmpegEncoder -FFmpegPath 'ffmpeg' -Encoder 'libx264' | Should -BeTrue
    }

    It 'Returns false when the test encode fails' {
        Mock Invoke-FFmpeg { throw 'ffmpeg exited with code 1: No capable devices found' }
        Test-FFmpegEncoder -FFmpegPath 'ffmpeg' -Encoder 'av1_nvenc' | Should -BeFalse
    }

    It 'Encodes a few generated frames with the encoder, to nowhere' {
        Mock Invoke-FFmpeg { [PSCustomObject]@{ ExitCode = 0; StandardOutput = @(); StandardError = @() } }
        $null = Test-FFmpegEncoder -FFmpegPath 'my ffmpeg' -Encoder 'hevc_nvenc'
        Should -Invoke Invoke-FFmpeg -ParameterFilter {
            $joined = $ArgumentList -join ' '
            $ExecutablePath -eq 'my ffmpeg' -and $joined -like '*-c:v hevc_nvenc*' -and $joined -like '*-f lavfi*' -and $joined -like '*-frames:v 3*' -and $ArgumentList[-1] -eq '-'
        }
    }

    It 'Rejects encoder names that are not plain names' {
        { Test-FFmpegEncoder -FFmpegPath 'ffmpeg' -Encoder 'libx264 -y out.mp4' } | Should -Throw
    }
}
