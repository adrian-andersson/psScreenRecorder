function new-psScreenRecord
{
<#
	.SYNOPSIS
		Simple Screen-Capture done in PowerShell

        Needs ffmpeg: https://www.ffmpeg.org/

	.DESCRIPTION
		Simple Screen-Capture done in PowerShell.
        Useful for making tutorial  and demonstration videos

        Also draws a big red dot where your cursor is, if it is in the defined window bounds

        Uses FFMPeg to make a video file
        Video file can then be edited in your fav video editor
        Like Blender :)


        You will need to download and setup FFMPEG first

        https://www.ffmpeg.org/

        The default path to the ffmpeg exe is c:\program files\ffmpeg\bin


    .PARAMETER videoName
		Name + Extension to output the video file as
        By default will use out.mp4

    .PARAMETER fps
		Framerate used to calculate both how often to take a screenshot
        And what to use to process the ffmpeg call

    .PARAMETER captureCursor
        Should we put a replacement cursor (Red-dot for visibility) in the video?

    .PARAMETER force
        Skip fileExists and remove check


    .PARAMETER outFolder
		The folder to save the output video to


    .PARAMETER ffMPegPath
		Path to ffMpeg
        Suggest you modify this to be where yours is by default


    .PARAMETER tempPath
        Where to store the images before compiling them into a video


	.EXAMPLE
		new-psScreenRecord -outFolder 'C:\temp\testVid' -Verbose

	DESCRIPTION
	------------
		Will create a new video file with 'out.mp4' filename in c:\temp\testVid folder


    .NOTES
		Author: Adrian Andersson



        Changelog

            2017-09-13  - AA
                - New script, cleaned-up from an old one I had saved

            2019-03-14 - AA
                - Moved to bartender module

            2019-03-14 - AA
                - Changed the ffmpegPath to use the allUsersProfile path
                - Throw better errors
                - Added a couple write-hosts so users were not left wondering what was going on with the capture process
                    - Normally I don't condone write-host but it seemed to make sense in this case
                -Changed var name to ffmpegArg
                - Moved images to temp folder rather than output folder
                - Fixed confirm switch so it actually works
                - Fixed the help

            2019-03-17 - AA
                - Second attempt at fixing screen scaling bug

            2019-03-20 - AA
                - Added a switch and the necessary call changes to not capture the cursor if it is undesired
                - Removed the requirement to confirm
                - Changed the output folder to be in the users documents + psScreenRecorder subfolder
                    - Old path was a bit untidy
                - Made confirm a 'force' switch as this is clearer language
                    - Also it should only ask to confirm on removing the existing video file
                - Changed the way we check for files to be a bit tidier
                - Return the output video path as a string
                - Removed the write-hosts and made them write warning instead
                - Added a hidden param for startCapture
                    - Can be used to skip the actual capture
                    - Left it in for debug purposes
                - Re-ordered the params
                    - Since videoName is the most important one now we have good defaults
                - If videoname does not end in .mp4, add it in
                - Added a check to see if mp4 is part of the video name, add it in if it isn't there

    .COMPONENT
        psScreenCapture
#>

    [CmdletBinding()]
    PARAM(
        [Alias("name")]
        [string]$videoName = 'out.mp4',
        [Alias("framerate")]
        [string]$fps = 24,
        [bool]$captureCursor = $true,
        [switch]$force,
        [Alias("path")]
        [string]$outFolder = "$($env:USERPROFILE)\documents\psScreenRecorder",
        [string]$ffMPegPath = $(get-childitem -path "$($env:ALLUSERSPROFILE)\ffmpeg" -filter 'ffmpeg.exe' -Recurse|sort-object -Property LastWriteTime -Descending|select-object -First 1).fullname,
        [string]$tempPath = "$($env:temp)\ffmpeg",
        [Parameter(DontShow)]
        [bool]$startCapture = $true,
        [Parameter(DontShow)]
        [switch]$leaveImages
    )
    begin{


        #Return the script name when running verbose, makes it tidier
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        #Return the sent variables when running debug
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"


        Write-Verbose 'Adding a new C# Assembly to get the Foreground Window'
        #This assembly is needed to get the current process
        #So we know when we have gone BACK to PowerShell
        #Use an array since its tidier than a here string
        $typeDefinition = @(
            'using System;',
            'using System.Runtime.InteropServices;',
            'public class UserWindows {',
            '   [DllImport("user32.dll")]',
            '   public static extern IntPtr GetForegroundWindow();',
            '}'
        )

        Add-Type $($typeDefinition -join "`n")

        write-verbose 'Loading other required assemblies'
        Add-Type -AssemblyName system.drawing
        add-type -AssemblyName system.windows.forms




        #We need to calculate the sleep-time based on the FPS
        #We want to know how many miliseconds to take a snap - as a whole number
        #Based on the frame-rate
        #This should be accurate enough
        write-verbose 'Calculating capture time'
        $msWait =[math]::Floor(1/$($fps/1000))

        write-verbose 'Checking videoName has extension'
        if($videoName.EndsWith('.mp4') -ne $true)
        {
            Write-Verbose 'Appending mp4 extension to video name since it was not supplied'
            $videoName = "$videoName.mp4"
        }


        write-verbose 'Generating output path'

        $outputFilePath = "$outFolder\$videoName"
        write-verbose "outputFilePath: $outputFilePath"


    }process{

        write-verbose 'Checking for ffmpeg'
        if(!$(test-path -Path $ffMPegPath -ErrorAction SilentlyContinue))
        {
            throw 'FFMPEG not found - either provide the path variable or run the install-ffmmpeg command'
        }

        if(!$(test-path $tempPath))
        {
            write-verbose 'Creating ffmpeg temp directory'
            try{
                $outputDir = new-item -ItemType Directory -Path $tempPath -Force -ErrorAction Stop
                write-verbose 'Directory Created'
            }catch{
                throw 'Unable to create ffmpeg temp directory'
            }
        }else{
            Write-Verbose 'Removing existing jpegs in folder and video file if it exists'
            remove-item "$tempPath\*.jpg" -Force
        }


        Write-Verbose 'Getting THIS POWERSHELL Session handle number so we know what to ignore'
        #This is used in conjunction with the above service, to identify when we get back to the ps window
        $thisWindowHandle = $(Get-Process -Name *powershell* |Where-Object{$_.MainWindowHandle -eq $([userwindows]::GetForegroundWindow())}).MainWindowHandle

        Write-Verbose 'Ensuring output folder is ok'
        if(Test-Path $outfolder -ErrorAction SilentlyContinue)
        {
            Write-Verbose 'Output folder already exists.'
            if(test-path $outputFilePath)
            {

                if(!$force)
                {
                    if($($Host.UI.PromptForChoice('Continue',"$outputFilePath already exists! Continue?", @('No','Yes'), 1)) -eq 1)
                    {
                        write-warning 'Removing file and continuing with screen capture'
                    }else{
                        return -1
                    }

                    remove-item $outputFilePath -Force -ErrorAction SilentlyContinue #SilentlyCont in case the file doesn't exist

                }


            }

        }else{
            Write-Verbose 'Creating new output folder'
            new-item -Path $outFolder -ItemType Directory -Force

        }


        #Get the window size
        Write-Verbose 'Getting the Window Size'
        Read-Host 'VIDEO RECORD, put mouse cursor in top left corner of capture area and press any key'
        $start = [System.Windows.Forms.Cursor]::Position
        Read-Host 'VIDEO RECORD, put mouse cursor in bottom right corner of capture area and press any key'
        $end = [System.Windows.Forms.Cursor]::Position

        $scale = get-screenScaling

        $horStart = get-EvenNumber $($($start.x * $scale))
        $verStart = get-EvenNumber $($($start.y * $scale))
        $horEnd = get-EvenNumber $($($end.x * $scale))
        $verEnd = get-EvenNumber $($($end.y * $scale))
        $boxSize = "box size: Xa: $horStart, Ya: $verStart, Xb: $horEnd, Yb: $verEnd, $($horEnd - $horStart) pixels wide, $($verEnd - $verStart) pixles tall"
        Write-Verbose $boxSize
        #$startCapture = $true - Used to be used by confirm block
        #But will leave it in here to quickly switch off capturing for debug purposes
        #Wil move $startCapture = $true to be a hiidden boolean at the top though

        if($startCapture -eq $true -or $startCapture -eq 1)
        {
            Write-warning 'Starting screen capture 2 seconds after this window looses focus'
            #Start up the capture process
            $num = 1 #Iteration number for screenshot naming
            $capture = $false #Switch to say when to stop capture
            #Wait for PowerShell to loose focus
            while($capture -eq $false)
            {
                if([userwindows]::GetForegroundWindow() -eq $thisWindowHandle)
                {
                    write-verbose 'Powershell still in focus'
                    Start-Sleep -Milliseconds 60
                }else{
                    write-verbose 'Powershell lost focus'
                    Write-warning 'Focus Lost - Starting screen capture in 2 seconds'
                    Start-Sleep -Seconds 2
                    Write-Warning 'Capturing Screen'
                    $capture=$true
                    $stopwatch = [System.Diagnostics.stopwatch]::StartNew()
                }
            }
            #Do another loop until PowerShell regains focus
            while($capture -eq $true)
            {
                if([userwindows]::GetForegroundWindow() -eq $thisWindowHandle)
                {
                    write-verbose 'Powershell has regained focus, so exit the loop'
                    $capture = $false
                }else{
                    write-verbose 'Powershell does not have focus, so capture a screenshot'
                    $x = "{0:D5}" -f $num
                    $path = "$tempPath\$x.jpg"
                    $screenshotSplat = @{
                        horStart = $horStart
                        vertStart = $verStart
                        horEnd = $horEnd
                        verEnd = $verEnd
                        path = $path
                        captureCursor = $captureCursor
                    }
                    #Out-screenshot -horStart $horStart -verStart $verStart -horEnd $horEnd -verEnd $verEnd -path $path -captureCursor
                    out-screenShot @screenshotSplat
                    $num++
                    Start-Sleep -milliseconds $msWait
                }
            }

        }else{
            return -1
        }


    }End{
        $stopwatch.stop()
        $numberOfImages = $(get-childitem $tempPath -Filter '*.jpg').count
        #Gasp ... a write host appeared
        #Since we aren't returning any objects this seems like a good option
        #We are now returning objects, so this needs to be changed to a warning
        Write-warning 'Capture complete, compiling video'
        $actualFrameRate = $numberOfImages / $stopwatch.Elapsed.TotalSeconds
        $actualFrameRate = [math]::Ceiling($actualFrameRate)
        Write-Verbose "Time Elapsed: $($stopwatch.Elapsed.ToString())"
        Write-Verbose "Total Number of Images: $numberOfImages"
        Write-Verbose "ActualFrameRate: $actualFrameRate"
        Write-Verbose 'Creating video using ffmpeg'
        $ffmpegArg = "-framerate $actualFrameRate -i $tempPath\%05d.jpg -c:v libx264 -vf fps=$actualFrameRate -pix_fmt yuv420p $outputFilePath -y"
        Start-Process -FilePath $ffMPegPath -ArgumentList $ffmpegArg -Wait
        if(!$leaveImages)
        {
            Write-Verbose 'Cleaning up jpegs'
            remove-item "$tempPath\*.jpg" -Force
        }else{
            write-warning "Leaving images in: $tempPath"
        }

        if(test-path $outputFilePath)
        {
            return $outputFilePath
        }else{
            throw 'Error - Unable to find newly created file'
        }


    }

}
