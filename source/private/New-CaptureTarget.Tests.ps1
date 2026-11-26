[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'New-CaptureTarget'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'New-CaptureTarget' {
    It 'Makes a capture target with the values given' {
        $target = New-CaptureTarget -Kind Monitor -Index 1 -Name 'DISPLAY2' -X -1920 -Y 0 -Width 1920 -Height 1080 -Handle 65539 -Dpi 144 -IsPrimary $true
        $target.PSTypeNames | Should -Contain 'psScreenRecorder.CaptureTarget'
        $target.Kind | Should -Be 'Monitor'
        $target.X | Should -Be -1920
        $target.Handle | Should -Be 65539
        $target.IsPrimary | Should -BeTrue
    }

    It 'Shows scaling as a percentage of 96 DPI' {
        (New-CaptureTarget -Kind Monitor -Dpi 144).Scaling | Should -Be '150%'
        (New-CaptureTarget -Kind Monitor -Dpi 96).Scaling | Should -Be '100%'
        (New-CaptureTarget -Kind Monitor).Scaling | Should -BeNullOrEmpty
    }

    It 'Leaves sizes empty when they are not known' {
        $target = New-CaptureTarget -Kind Monitor -DeviceIndex 1
        $target.Width | Should -BeNullOrEmpty
        $target.DeviceIndex | Should -Be 1
    }

    It 'Keeps the monitor a region sits inside' {
        $monitor = New-CaptureTarget -Kind Monitor -Name 'm'
        (New-CaptureTarget -Kind Region -Monitor $monitor).Monitor.Name | Should -Be 'm'
    }

    It 'Shows a short default set of properties' {
        $target = New-CaptureTarget -Kind Window -Name 'w'
        $target.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Contain 'Kind'
        $target.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Not -Contain 'Handle'
    }

    It 'Rejects an unknown kind' {
        { New-CaptureTarget -Kind 'Universe' } | Should -Throw
    }
}
