[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'Get-ProcessAncestor.ps1'
        'Get-ForegroundWindowHandle.ps1'
        'Get-NativeWindowInfo.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Get-TerminalWindowHandle'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Get-TerminalWindowHandle' {
    BeforeEach {
        #pwsh (10) started by WindowsTerminal (20), which owns window 555
        Mock Get-ProcessAncestor {
            [PSCustomObject]@{ Id = 10; ProcessName = 'pwsh'; MainWindowHandle = [IntPtr]::Zero }
            [PSCustomObject]@{ Id = 20; ProcessName = 'WindowsTerminal'; MainWindowHandle = [IntPtr]555 }
        }
    }

    It 'Uses the focused window when it belongs to this session''s process chain' {
        Mock Get-ForegroundWindowHandle { 777 }
        Mock Get-NativeWindowInfo { [PSCustomObject]@{ ProcessId = 20; Title = 'Terminal tab' } }
        Get-TerminalWindowHandle | Should -Be 777
    }

    It 'Uses the nearest ancestor''s main window when another app has focus' {
        Mock Get-ForegroundWindowHandle { 888 }
        Mock Get-NativeWindowInfo { [PSCustomObject]@{ ProcessId = 99; Title = 'A browser' } }
        Get-TerminalWindowHandle | Should -Be 555
    }

    It 'Uses the ancestor''s window when nothing has focus' {
        Mock Get-ForegroundWindowHandle { 0 }
        Mock Get-NativeWindowInfo {}
        Get-TerminalWindowHandle | Should -Be 555
    }

    It 'Throws when no process in the chain has a window, as in a service' {
        Mock Get-ProcessAncestor { [PSCustomObject]@{ Id = 10; ProcessName = 'pwsh'; MainWindowHandle = [IntPtr]::Zero } }
        Mock Get-ForegroundWindowHandle { 0 }
        Mock Get-NativeWindowInfo {}
        { Get-TerminalWindowHandle } | Should -Throw '*Unable to find the window*'
    }
}

Describe 'Get-ProcessAncestor' {
    It 'Starts with this session and walks up to the processes that started it' {
        $chain = @(Get-ProcessAncestor)
        $chain[0].Id | Should -Be $PID
        $chain.Count | Should -BeGreaterThan 1
    }

    It 'Returns nothing for a process that does not exist' {
        Get-ProcessAncestor -ProcessId 999999 | Should -BeNullOrEmpty
    }
}
