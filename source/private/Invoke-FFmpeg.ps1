function Invoke-FFmpeg
{
    <#
        .SYNOPSIS
            Run ffmpeg or ffprobe to completion and return what it wrote

        .DESCRIPTION
            Every call to ffmpeg and ffprobe goes through this function, so the rest of the module only
            has to build an argument list, and tests only have to mock this.

            Arguments go in as an array, one element per argument, so paths with spaces and filter graphs
            with quotes, commas and semicolons are passed through untouched. There is no string to quote.

            stdout and stderr are collected separately. A non-zero exit code throws, with the last lines
            of stderr in the message, since that is where ffmpeg explains what went wrong.

            With -ProgressActivity, '-progress pipe:1 -nostats' is added to the arguments and the
            key=value progress blocks ffmpeg writes to stdout drive Write-Progress. Give -ExpectedDuration
            as well to show a percentage.

        .NOTES
            Author: Adrian Andersson

            Long-running recordings, which need a handle on the process to stop it, use
            Start-FFmpegProcess instead.

        .EXAMPLE
            Invoke-FFmpeg -ArgumentList '-hide_banner','-version'

            #### DESCRIPTION
            Run ffmpeg -version. The output is in the StandardOutput property of the result.

        .EXAMPLE
            Invoke-FFmpeg -Tool ffprobe -ArgumentList '-v','error','-print_format','json','-show_format','C:\Videos\my clip.mp4'

            #### DESCRIPTION
            Run ffprobe on a file whose path has a space in it, with no quoting needed.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM(
        #Arguments for the tool, one element per argument
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ArgumentList,
        #Which tool to run
        [Parameter()]
        [ValidateSet('ffmpeg','ffprobe')]
        [string]$Tool = 'ffmpeg',
        #Show progress with Write-Progress under this activity name
        [Parameter()]
        [string]$ProgressActivity,
        #How long the output should be, so progress can show a percentage
        [Parameter()]
        [timespan]$ExpectedDuration,
        #Run this executable instead of the one Find-FFmpeg finds. Used by Find-FFmpeg itself
        [Parameter(DontShow)]
        [string]$ExecutablePath
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"

        #A non-zero exit is handled below with a better message than the generic native command error
        $PSNativeCommandUseErrorActionPreference = $false
        #How many lines of stderr to put in the exception message
        $errorTailLength = 8
    }
    process{
        if(!$ExecutablePath)
        {
            write-verbose 'No executable given, asking Find-FFmpeg'
            $installation = Find-FFmpeg
            $ExecutablePath = $(if($Tool -eq 'ffprobe'){$installation.FFprobePath}else{$installation.FFmpegPath})
            if(!$ExecutablePath)
            {
                throw "$Tool was not found alongside ffmpeg ($($installation.FFmpegPath)) or on PATH"
            }
        }
        write-verbose "Executable: $ExecutablePath"

        $fullArgumentList = [System.Collections.Generic.List[string]]::new()
        if($ProgressActivity)
        {
            $fullArgumentList.AddRange([string[]]@('-progress','pipe:1','-nostats'))
        }
        $fullArgumentList.AddRange($ArgumentList)
        write-verbose "Arguments: $($fullArgumentList -join ' ')"

        $standardOutput = [System.Collections.Generic.List[string]]::new()
        $standardError = [System.Collections.Generic.List[string]]::new()
        $hasExpectedDuration = $PSBoundParameters.ContainsKey('ExpectedDuration') -and $ExpectedDuration.TotalSeconds -gt 0

        #ffmpeg and ffprobe write UTF-8. Without this, non-ASCII file names in ffprobe's JSON get mangled on Windows
        $previousEncoding = $null
        try{
            $previousEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        }catch{
            write-verbose 'No console to set the output encoding on, leaving it as it is'
        }

        try{
            & $ExecutablePath @fullArgumentList 2>&1 | ForEach-Object {
                if($_ -is [System.Management.Automation.ErrorRecord])
                {
                    $standardError.Add($_.ToString())
                    return
                }
                $line = [string]$_
                $standardOutput.Add($line)
                if($ProgressActivity -and $line -match '^out_time_us=(\d+)$')
                {
                    $elapsed = [timespan]::FromTicks([long]$Matches[1] * 10)
                    $progressSplat = @{
                        Activity = $ProgressActivity
                        Status = "$($elapsed.ToString('hh\:mm\:ss'))"
                    }
                    if($hasExpectedDuration)
                    {
                        $progressSplat.PercentComplete = [math]::Min(100,[math]::Floor(($elapsed.TotalSeconds / $ExpectedDuration.TotalSeconds) * 100))
                    }
                    Write-Progress @progressSplat
                }
            }
            $exitCode = $LASTEXITCODE
        }finally{
            if($ProgressActivity)
            {
                Write-Progress -Activity $ProgressActivity -Completed
            }
            if($previousEncoding)
            {
                try{ [Console]::OutputEncoding = $previousEncoding }catch{ write-verbose 'Unable to restore the console output encoding' }
            }
        }

        write-verbose "$Tool exited with code: $exitCode"
        if($exitCode -ne 0)
        {
            $tail = $standardError | Select-Object -Last $errorTailLength
            throw "$Tool exited with code $($exitCode): $($tail -join [Environment]::NewLine)"
        }

        [PSCustomObject]@{
            PSTypeName = 'psScreenRecorder.FFmpegResult'
            ExitCode = $exitCode
            StandardOutput = $standardOutput.ToArray()
            StandardError = $standardError.ToArray()
        }
    }
}
