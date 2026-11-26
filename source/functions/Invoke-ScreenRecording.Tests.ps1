[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

#Recording a real script block runs in tests/Recording.Integration.Tests.ps1
BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'ToTimeSpanAttribute.ps1'
        'Start-ScreenRecording.ps1'
        'Stop-ScreenRecording.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Invoke-ScreenRecording'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-ScreenRecording' {
    BeforeEach {
        $script:order = [System.Collections.Generic.List[string]]::new()
        Mock Start-ScreenRecording { $script:order.Add('start'); [PSCustomObject]@{ PSTypeName = 'psScreenRecorder.Recording'; Id = 1 } }
        Mock Stop-ScreenRecording { $script:order.Add('stop'); [System.IO.FileInfo]::new('demo.mp4') }
        Mock Start-Sleep { $script:order.Add("sleep $Milliseconds") }
        Mock Clear-Host { $script:order.Add('clear') }
    }

    It 'Starts, waits the lead-in, runs the script block, waits the lead-out, then stops and returns the file' {
        $file = Invoke-ScreenRecording -LeadIn 0.5 -LeadOut 2 -ScriptBlock { $script:order.Add('script') }
        $file.Name | Should -Be 'demo.mp4'
        $script:order | Should -Be @('start','sleep 500','script','sleep 2000','stop')
    }

    It 'Clears the screen before recording with -ClearHost' {
        $null = Invoke-ScreenRecording -ClearHost -ScriptBlock {}
        $script:order[0] | Should -Be 'clear'
        $script:order[1] | Should -Be 'start'
    }

    It 'Records the current terminal by default on Windows, and the primary monitor elsewhere' {
        $null = Invoke-ScreenRecording -ScriptBlock {}
        if($IsWindows)
        {
            Should -Invoke Start-ScreenRecording -ParameterFilter { $CurrentTerminal }
        }else{
            Should -Invoke Start-ScreenRecording -ParameterFilter { !$CurrentTerminal -and !$PSBoundParameters.ContainsKey('Monitor') }
        }
    }

    It 'Passes what to record, and how, on to Start-ScreenRecording' {
        $null = Invoke-ScreenRecording -Monitor 1 -Fps 15 -Codec HEVC -Path 'x.mp4' -HideCursor -ScriptBlock {}
        Should -Invoke Start-ScreenRecording -ParameterFilter { $Monitor -eq 1 -and $Fps -eq 15 -and $Codec -eq 'HEVC' -and $Path -eq 'x.mp4' -and $HideCursor }
    }

    It 'Passes -Rectangle on' {
        $null = Invoke-ScreenRecording -Rectangle 1,2,30,40 -ScriptBlock {}
        Should -Invoke Start-ScreenRecording -ParameterFilter { ($Rectangle -join ',') -eq '1,2,30,40' }
    }

    It 'Saves the recording, then writes the error, when the script block fails' {
        $file = Invoke-ScreenRecording -ScriptBlock { throw 'demo broke' } -ErrorVariable problems -ErrorAction SilentlyContinue
        $file.Name | Should -Be 'demo.mp4'
        $script:order[-1] | Should -Be 'stop'
        #ErrorVariable also records the error as it was caught inside, so check it's there rather than count
        $problems.Where{ $_.ToString() -like '*demo broke*' }.Count | Should -BeGreaterThan 0
    }

    It 'Returns nothing when the recording didn''t start, such as a cancelled selection' {
        Mock Start-ScreenRecording {}
        Invoke-ScreenRecording -ScriptBlock { $script:order.Add('script') } | Should -BeNullOrEmpty
        $script:order | Should -Not -Contain 'script'
    }

    It 'Throws for a negative lead-in or lead-out' {
        { Invoke-ScreenRecording -LeadOut -1 -ScriptBlock {} } | Should -Throw '*cannot be negative*'
    }
}
