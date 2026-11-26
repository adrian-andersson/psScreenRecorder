function Select-CaptureBackend
{
    <#
        .SYNOPSIS
            Choose which ffmpeg capture source records a target

        .DESCRIPTION
            Picks the best capture source the ffmpeg build has for the target, or checks one that was asked
            for can actually record it.

            Windows, best first:
              gfxcapture  Windows.Graphics.Capture (ffmpeg 8.1+). Records a window even when it's covered,
                          and finds monitors by handle, so there's no index to get wrong
              ddagrab     Desktop Duplication (ffmpeg 6+). Used for monitors and regions only when there is a
                          single monitor, because its output numbering hasn't been confirmed to match Windows'
                          monitor order on machines with several
              gdigrab     GDI. Works everywhere, and uses virtual desktop coordinates, so it handles regions
                          that span monitors. Slower, and records a window by its area on screen, so anything
                          covering the window is recorded too
            macOS: avfoundation. Linux: x11grab. Synthetic targets: synthetic.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Select-CaptureBackend -Target $monitor -AvailableSources 'gfxcapture','ddagrab','gdigrab' -MonitorCount 2

            #### DESCRIPTION
            Returns 'gfxcapture'.
    #>

    [CmdletBinding()]
    [OutputType([string])]
    PARAM(
        #The capture target
        [Parameter(Mandatory)]
        [PSCustomObject]$Target,
        #Capture sources the ffmpeg build has, from Find-FFmpeg -IncludeCapability
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$AvailableSources = @(),
        #The capture source asked for, or Auto to choose
        [Parameter()]
        [ValidateSet('Auto','gfxcapture','ddagrab','gdigrab','avfoundation','x11grab','synthetic')]
        [string]$Requested = 'Auto',
        #How many monitors there are. ddagrab is only chosen automatically when there is one
        [Parameter()]
        [int]$MonitorCount = 1,
        #The platform to choose for. Defaults to this one
        [Parameter(DontShow)]
        [ValidateSet('Windows','macOS','Linux')]
        [string]$Platform = $(if($IsWindows){'Windows'}elseif($IsMacOS){'macOS'}else{'Linux'})
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        $platformSources = @{
            Windows = @('gfxcapture','ddagrab','gdigrab')
            macOS = @('avfoundation')
            Linux = @('x11grab')
        }
    }
    process{
        $kind = $Target.Kind
        if($kind -eq 'Synthetic')
        {
            if($Requested -notin 'Auto','synthetic')
            {
                throw "A synthetic target can only use the synthetic source, not $Requested"
            }
            return 'synthetic'
        }
        if($Requested -eq 'synthetic')
        {
            throw 'The synthetic source can only record a synthetic target'
        }
        if($kind -eq 'Window' -and $Platform -ne 'Windows')
        {
            throw "Recording a single window is only supported on Windows for now. On $Platform, record a monitor, or a region with -Rectangle"
        }
        #A region that spans monitors has no single monitor to hand gfxcapture or ddagrab
        $fitsOneMonitor = $kind -ne 'Region' -or $null -ne $Target.Monitor

        if($Requested -ne 'Auto')
        {
            if($Requested -notin $platformSources[$Platform])
            {
                throw "$Requested is not a $Platform capture source. Use one of: $($platformSources[$Platform] -join ', ')"
            }
            if($Requested -notin $AvailableSources)
            {
                throw "This ffmpeg build does not have $Requested. It has: $(if($AvailableSources){$AvailableSources -join ', '}else{'no screen capture sources'})"
            }
            if($kind -eq 'Window' -and $Requested -eq 'ddagrab')
            {
                throw 'ddagrab records monitors, not windows. Use gfxcapture or gdigrab for a window'
            }
            if(!$fitsOneMonitor -and $Requested -in 'gfxcapture','ddagrab')
            {
                throw "The region spans more than one monitor, which $Requested can't record. Use gdigrab, or a region inside one monitor"
            }
            return $Requested
        }

        $candidates = switch($Platform)
        {
            'Windows' {
                if($kind -eq 'Window')
                {
                    'gfxcapture','gdigrab'
                }elseif($fitsOneMonitor){
                    'gfxcapture'
                    if($MonitorCount -le 1){ 'ddagrab' }
                    'gdigrab'
                }else{
                    'gdigrab'
                }
            }
            'macOS' { 'avfoundation' }
            'Linux' { 'x11grab' }
        }
        foreach($candidate in $candidates)
        {
            if($candidate -in $AvailableSources)
            {
                write-verbose "Chose $candidate for the $kind"
                return $candidate
            }
        }
        throw "This ffmpeg build has no screen capture source psScreenRecorder can use on $Platform. It needs one of: $($platformSources[$Platform] -join ', '). Builds from your package manager, or from ffmpeg.org, normally include them"
    }
}
