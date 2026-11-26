[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

#The native helper and its thin wrappers, on a real Windows desktop. Elsewhere, only the refusal is tested
BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'Get-NativeMonitorInfo.ps1'
        'Get-NativeWindowInfo.ps1'
        'Get-ForegroundWindowHandle.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Initialize-ScreenRecorderNative'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Initialize-ScreenRecorderNative' {
    It 'Refuses to load anywhere but Windows' -Skip:$IsWindows {
        { Initialize-ScreenRecorderNative } | Should -Throw '*only available on Windows*'
    }

    Context 'On Windows' -Skip:(!$IsWindows) {
        It 'Compiles the helper, and does nothing the second time' {
            Initialize-ScreenRecorderNative
            'PsScreenRecorder.Native' -as [type] | Should -Not -BeNullOrEmpty
            { Initialize-ScreenRecorderNative } | Should -Not -Throw
        }

        It 'Lists at least one monitor, with a size and a primary' {
            $monitors = @(Get-NativeMonitorInfo)
            $monitors.Count | Should -BeGreaterThan 0
            $monitors[0].Width | Should -BeGreaterThan 0
            @($monitors.Where{ $_.IsPrimary }).Count | Should -Be 1
        }

        It 'Returns nothing for a window handle that does not exist' {
            Get-NativeWindowInfo -Handle 1 | Should -BeNullOrEmpty
        }

        It 'Lists windows without failing, and reports the focused window as a number' {
            { Get-NativeWindowInfo } | Should -Not -Throw
            Get-ForegroundWindowHandle | Should -BeOfType [long]
        }

        It 'Puts the thread''s DPI awareness back afterwards' {
            Add-Type -Namespace PsScreenRecorderTest -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetThreadDpiAwarenessContext();
[DllImport("user32.dll")] public static extern int GetAwarenessFromDpiAwarenessContext(IntPtr context);
'@ -ErrorAction SilentlyContinue
            $before = [PsScreenRecorderTest.Dpi]::GetAwarenessFromDpiAwarenessContext([PsScreenRecorderTest.Dpi]::GetThreadDpiAwarenessContext())
            $null = Get-NativeMonitorInfo
            [PsScreenRecorderTest.Dpi]::GetAwarenessFromDpiAwarenessContext([PsScreenRecorderTest.Dpi]::GetThreadDpiAwarenessContext()) | Should -Be $before
        }
    }
}
