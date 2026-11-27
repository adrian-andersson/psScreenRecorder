function Invoke-ScreenRecording
{
    <#
        .SYNOPSIS
            Record a script block running, start to finish. Made for README demos

        .DESCRIPTION
            Starts recording, waits -LeadIn so the video opens on a still frame, runs the script block, waits
            -LeadOut so the result stays on screen long enough to read, then stops and returns the saved file.

            By default it records the terminal window it's running in (Windows), or the primary monitor
            elsewhere. -Monitor, -Rectangle or -Target record something else instead.

            The script block's output goes to the screen, so it appears in the recording. -ClearHost clears the
            screen first, so the video starts clean. If the script block fails, the recording is still saved
            and returned, and the error is written afterwards.

            The recording options (-Path, -Fps, -Quality, -Codec, -Encoder, -HideCursor) are passed to
            Start-ScreenRecording. Pipe the result to ConvertTo-Gif for a README.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Invoke-ScreenRecording -ClearHost -ScriptBlock { Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 } |
                ConvertTo-Gif -Destination .\docs\demo.gif -RemoveDuplicateFrames

            #### DESCRIPTION
            Record this terminal showing the busiest processes, and make a GIF of it for the docs.

        .EXAMPLE
            Invoke-ScreenRecording -Monitor 1 -LeadOut 3 -ScriptBlock { Start-Process notepad; Start-Sleep 5 }

            #### DESCRIPTION
            Record monitor 1 while Notepad opens, holding the end for three seconds.
    #>

    [CmdletBinding(DefaultParameterSetName='CurrentTerminal')]
    [OutputType([System.IO.FileInfo])]
    PARAM(
        #The script block to run while recording
        [Parameter(Mandatory,Position=0)]
        [scriptblock]$ScriptBlock,
        #Record a monitor, by its Index from Get-CaptureTarget, instead of the terminal
        [Parameter(Mandatory,ParameterSetName='Monitor')]
        [ValidateRange(0,64)]
        [ArgumentCompleter({
            #Completers run outside the module, so run the private helper inside it. Dot-sourced, as in tests, there is no module
            $module = (Get-Command -Name $args[0] -ErrorAction Ignore).Module
            if($module){ & $module { Get-CaptureTargetCompletion -Kind Monitor -WordToComplete $args[0] } $args[2] }else{ Get-CaptureTargetCompletion -Kind Monitor -WordToComplete $args[2] }
        })]
        [int]$Monitor,
        #Record an area, as X,Y,Width,Height in physical pixels, instead of the terminal
        [Parameter(Mandatory,ParameterSetName='Rectangle')]
        [ValidateCount(4,4)]
        [int[]]$Rectangle,
        #Record this target, from Get-CaptureTarget or Select-ScreenRegion, instead of the terminal
        [Parameter(Mandatory,ParameterSetName='Target')]
        [PSTypeName('psScreenRecorder.CaptureTarget')]
        [PSCustomObject]$Target,
        #Record a generated test pattern instead of the screen. Used by tests
        [Parameter(Mandatory,ParameterSetName='Synthetic',DontShow)]
        [switch]$Synthetic,
        #How long to record before running the script block: seconds, mm:ss or hh:mm:ss
        [Parameter()]
        [ToTimeSpan()]
        [timespan]$LeadIn = [timespan]::FromSeconds(0.5),
        #How long to keep recording after the script block ends: seconds, mm:ss or hh:mm:ss
        [Parameter()]
        [ToTimeSpan()]
        [timespan]$LeadOut = [timespan]::FromSeconds(1.5),
        #Clear the screen before recording starts
        [Parameter()]
        [switch]$ClearHost,
        #File or folder to save to. Defaults to the Videos folder
        [Parameter()]
        [string]$Path,
        #Frames per second
        [Parameter()]
        [ValidateRange(1,120)]
        [int]$Fps = 30,
        #High, Standard, or Lossless
        [Parameter()]
        [ValidateSet('High','Standard','Lossless')]
        [string]$Quality = 'High',
        #Video codec
        [Parameter()]
        [ValidateSet('H264','HEVC','AV1')]
        [string]$Codec = 'H264',
        #Encoder family. Auto uses hardware when it works, then software
        [Parameter()]
        [ValidateSet('Auto','Software','Nvenc','Qsv','Amf','MediaFoundation','VideoToolbox')]
        [string]$Encoder = 'Auto',
        #Leave the mouse pointer out of the recording
        [Parameter()]
        [switch]$HideCursor,
        #Overwrite the file if it exists
        [Parameter()]
        [switch]$Force
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"
        $passThrough = @('Path','Fps','Quality','Codec','Encoder','HideCursor','Force')
    }
    process{
        if($LeadIn -lt [timespan]::Zero -or $LeadOut -lt [timespan]::Zero)
        {
            throw 'LeadIn and LeadOut cannot be negative'
        }
        $startSplat = @{ ErrorAction = 'Stop' }
        foreach($name in $passThrough)
        {
            if($PSBoundParameters.ContainsKey($name))
            {
                $startSplat[$name] = $PSBoundParameters[$name]
            }
        }
        switch($PSCmdlet.ParameterSetName)
        {
            'CurrentTerminal' {
                #Only Windows can record a single window. Elsewhere, the primary monitor shows the terminal too
                if($IsWindows){ $startSplat.CurrentTerminal = $true }
            }
            'Monitor' { $startSplat.Monitor = $Monitor }
            'Rectangle' { $startSplat.Rectangle = $Rectangle }
            'Target' { $startSplat.Target = $Target }
            'Synthetic' { $startSplat.Synthetic = $true }
        }

        if($ClearHost)
        {
            Clear-Host
        }
        $recording = Start-ScreenRecording @startSplat
        if(!$recording)
        {
            return
        }

        $scriptError = $null
        try{
            Start-Sleep -Milliseconds ([int]$LeadIn.TotalMilliseconds)
            try{
                & $ScriptBlock | Out-Host
            }catch{
                $scriptError = $_
            }
            Start-Sleep -Milliseconds ([int]$LeadOut.TotalMilliseconds)
        }finally{
            #Ctrl+C lands here too, so the recording is saved rather than left running
            $saved = Stop-ScreenRecording -Recording $recording -Confirm:$false
        }
        $saved
        if($scriptError)
        {
            Write-Error -ErrorRecord $scriptError
        }
    }
}
