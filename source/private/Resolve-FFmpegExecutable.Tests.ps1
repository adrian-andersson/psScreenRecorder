[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Resolve-FFmpegExecutable'
    . $fileName

    $extension = $(if($IsWindows){'.exe'}else{''})
    $folder = Join-Path -Path $TestDrive -ChildPath 'bin folder'
    $null = New-Item -ItemType Directory -Path $folder -Force
    $ffmpeg = Join-Path -Path $folder -ChildPath "ffmpeg$extension"
    $null = New-Item -ItemType File -Path $ffmpeg -Force
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-FFmpegExecutable' {
    It 'Finds the tool in a folder, adding .exe on Windows' {
        Resolve-FFmpegExecutable -Path $folder -Name 'ffmpeg' | Should -Be $ffmpeg
    }

    It 'Returns a file path given directly' {
        Resolve-FFmpegExecutable -Path $ffmpeg | Should -Be $ffmpeg
    }

    It 'Returns nothing when the tool is not in the folder' {
        Resolve-FFmpegExecutable -Path $folder -Name 'ffprobe' | Should -BeNullOrEmpty
    }

    It 'Returns nothing for a path that does not exist' {
        Resolve-FFmpegExecutable -Path (Join-Path -Path $TestDrive -ChildPath 'nothing here') | Should -BeNullOrEmpty
    }
}
