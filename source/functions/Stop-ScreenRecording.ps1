function Stop-ScreenRecording
{
    <#
        .SYNOPSIS
            Stop a recording and save it

        .DESCRIPTION
            Asks ffmpeg to stop (by sending it 'q', its own way of finishing cleanly), waits for it to finish
            writing, then saves the recording to its final file and returns that file.

            With no parameters, stops every recording this session is still running, which is usually the one.
            Give -Recording, or -Id, to stop a particular one. -AllSessions also stops or finishes recordings
            other PowerShell sessions are running or left behind. If there's nothing to stop here but other
            sessions have recordings, the warning says so.

            A recording that has already ended by itself, because its -Duration ran out, is saved.

            Recordings from other PowerShell sessions, from Get-ScreenRecording -AllSessions, can be piped in
            too. A running one is stopped (SIGINT on macOS and Linux; ended on Windows, losing at most the last
            second), and an abandoned one is finished. Either way it's repaired into the file it was going to be.

            The returned file has Duration, Width, Height, FrameRate and VideoCodec added, and pipes straight
            into ConvertTo-Gif.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Stop-ScreenRecording

            #### DESCRIPTION
            Stop and save whatever is recording.

        .EXAMPLE
            Stop-ScreenRecording | ConvertTo-Gif -Width 640 -RemoveDuplicateFrames

            #### DESCRIPTION
            Stop, save, and make a GIF of the recording.

        .EXAMPLE
            Get-ScreenRecording -Id 2 | Stop-ScreenRecording

            #### DESCRIPTION
            Stop recording number 2 only.

        .EXAMPLE
            Stop-ScreenRecording -AllSessions

            #### DESCRIPTION
            Stop and save everything recording anywhere, and finish recordings closed terminals left behind.
    #>

    [CmdletBinding(DefaultParameterSetName='All',SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    PARAM(
        #The recording to stop, from Start-ScreenRecording or Get-ScreenRecording
        [Parameter(Mandatory,ParameterSetName='Recording',ValueFromPipeline,Position=0)]
        [PSTypeName('psScreenRecorder.Recording')]
        [PSCustomObject[]]$Recording,
        #The Id of the recording to stop
        [Parameter(Mandatory,ParameterSetName='Id')]
        [int[]]$Id,
        #Also stop, or finish, recordings other PowerShell sessions started or left behind
        [Parameter(ParameterSetName='All')]
        [switch]$AllSessions,
        #How long to give ffmpeg to finish writing before it's ended: seconds, mm:ss or hh:mm:ss
        [Parameter()]
        [ToTimeSpan()]
        [timespan]$Timeout = [timespan]::FromSeconds(20)
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"
        $known = $(if($script:psScreenRecorderRecordings){@($script:psScreenRecorderRecordings)}else{@()})
    }
    process{
        $toStop = switch($PSCmdlet.ParameterSetName)
        {
            'Recording' { $Recording }
            'Id' {
                foreach($wanted in $Id)
                {
                    $found = $known | Where-Object { $_.Id -eq $wanted }
                    if(!$found)
                    {
                        Write-Error "There is no recording with Id $wanted"
                    }
                    $found
                }
            }
            'All' {
                $running = @($known | Where-Object { $_.State -in 'Recording','Ended' })
                $others = @(Get-OtherSessionRecording | Where-Object { $_.State -in 'Recording','Abandoned' })
                if($AllSessions)
                {
                    $running = @($running) + @($others)
                }
                if(!$running)
                {
                    if($others)
                    {
                        Write-Warning "There are no recordings to stop in this session, but other sessions have $($others.Count): $(($others | ForEach-Object { "$($_.State.ToLower()) $([System.IO.Path]::GetFileName($_.Path))" }) -join ', '). Use Stop-ScreenRecording -AllSessions to stop and save them"
                    }else{
                        Write-Warning 'There are no recordings to stop'
                    }
                }
                $running
            }
        }

        foreach($item in $toStop)
        {
            if($item.PSObject.Properties['Session'] -and $item.Session -eq 'Other' -and $item.State -in 'Recording','Abandoned')
            {
                Stop-OtherSessionRecording -Recording $item -Timeout $Timeout -Confirm:$false -WhatIf:$WhatIfPreference
                continue
            }
            if($item.State -eq 'Saved')
            {
                write-verbose "Recording $($item.Id) is already saved"
                Get-Item -LiteralPath $item.Path -ErrorAction SilentlyContinue
                continue
            }
            if($item.State -eq 'Failed')
            {
                Write-Error "Recording $($item.Id) failed: $($item.Error)"
                continue
            }
            if(!$PSCmdlet.ShouldProcess($item.Path, "Stop recording $($item.Id) and save it"))
            {
                continue
            }
            $exitInfo = Stop-FFmpegProcess -Handle $item.Handle -Timeout $Timeout -Confirm:$false
            Complete-ScreenRecording -Recording $item -ExitInfo $exitInfo
        }
    }
}
