<#
Module Mixed by BarTender
	A Framework for making PowerShell Modules
	Version: 6.1.22
	Author: Adrian.Andersson
	Copyright: 2019 Domain Group

Module Details:
	Module: psScreenRecorder
	Description: Desktop Video Capture with PowerShell
	Revision: 1.0.7.8
	Author: Adrian.Andersson
	Company: Adrian Andersson

Check Manifest for more details
#>

function convert-mp4togif
{
<#
	.SYNOPSIS
		Use FFMPEG to convert an mp4 to a gif
    .DESCRIPTION

		Use FFMPEG to convert an mp4 to a gif



	.PARAMETER mp4Path
		path to the mp4File

    .PARAMETER gifPath
        path to export the gif file

    .PARAMETER ffMPegPath
		Path to ffMpeg
        Suggest you modify this to be where yours is by default

    .PARAMETER tempPath
        Where to keep the palette file

    .PARAMETER fps
        The FPS to use for the gif

    .PARAMETER scale
        Use this to set the scale
        Seems to be horizontal resolution


	.EXAMPLE
		convert-mp4togif -mp4Path c:\input.mp4 -gifPath c:\output.gif


    .NOTES
		Author: Adrian Andersson

        Changelog

            2019-03-14 - AA
                - Initial Script

            2019-06-20 - AA
                - Added FPS and Scale


    .COMPONENT
        psScreenCapture
#>

    [CmdletBinding()]
    PARAM(
        [Parameter(Mandatory=$true,Position=0)]
        [Alias("path")]
        [string]$mp4Path,
        [Parameter(Mandatory=$true,Position=1)]
        [Alias("destination")]
        [string]$gifPath,
        [string]$ffMPegPath = $(get-childitem -path "$($env:ALLUSERSPROFILE)\ffmpeg" -filter 'ffmpeg.exe' -Recurse|sort-object -Property LastWriteTime -Descending|select-object -First 1).fullname,
        [string]$tempPath = "$($env:temp)\ffmpeg",
        [ValidateRange(1,60)]
        [int]$fps = 10,
        [int]$scale = 320
    )
    begin{


        #Return the script name when running verbose, makes it tidier
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        #Return the sent variables when running debug
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"

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
        }


        write-verbose 'Checking the input MP4 file'
        if(!$(test-path $mp4Path))
        {
            throw "Input MP4: $mp4Path not found"
        }else{
            $mp4File = $(get-item $mp4Path)
            $mp4Path = $mp4File.FullName
        }

        if(!$mp4Path -or ($mp4File.extension -ne '.mp4'))
        {
            throw "Error parsing mp4path"
        }


        if(test-path $gifPath)
        {
            write-warning "$gifpath exists and will be removed"
            try{
                remove-item $gifPath -Force
            }catch{
                write-warning 'Unable to remove existing file'
            }

        }


        write-verbose 'Making Frames'
        $palettePath = "$($(get-item $tempPath).fullname)\palette.png"
        #$filters = "fps=$fps,scale=320:-1:flags=lanczos"
        #$scale = 1200
        $filters = "fps=$fps,scale=$($scale):-1:flags=lanczos"

        $ffmpegArg = "  -i $mp4Path -vf `"$filters,palettegen`" -y $($palettePath)"
        Start-Process -FilePath $ffMPegPath -ArgumentList $ffmpegArg -Wait

        write-verbose 'Creating GIF using palette'
        $ffmpegArg = " -i $($mp4Path) -i $($palettePath) -filter_complex `"$filters[x];[x][1:v]paletteuse`" $gifPath"
        Start-Process -FilePath $ffMPegPath -ArgumentList $ffmpegArg -Wait

    }

}

function install-ffMpeg
{

    <#
        .SYNOPSIS
            Download ffmpeg
            
        .DESCRIPTION
            Download FFMPEG zip file
            Extract to allUsersProfile folder
            
        .PARAMETER ffmpegUri
            URI for where the zip file lives

        .PARAMETER tempPath
            Path to save the zip file

        .PARAMETER installPath
            Where to extract the zip file
            
        ------------
        .EXAMPLE
            install-ffMpeg
            
            
            
        .NOTES
            Author: Adrian Andersson
            
            
            Changelog:

                2019-03-14 - AA
                    - Initial Script
                    - Tested and working
                    
        .COMPONENT
            psScreenRecorder
    #>

    [CmdletBinding()]
    PARAM(
        [string]$ffmpegUri = 'https://ffmpeg.zeranoe.com/builds/win64/static/ffmpeg-20190312-d227ed5-win64-static.zip',
        [string]$tempPath = "$($env:temp)\ffmpeg.zip",
        [string]$installPath = "$($env:ALLUSERSPROFILE)\ffmpeg"

    )
    begin{
        #Return the script name when running verbose, makes it tidier
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        #Return the sent variables when running debug
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"
        
    }
    
    process{
        write-verbose 'Download ffmpeg'
        try{
            Invoke-WebRequest -Uri $ffmpegUri -OutFile $tempPath -ErrorAction Stop
        }catch{
            throw 'Unable to download ffmpeg'
        }

        write-verbose 'Checking for install folder'
        if(!(test-path $installPath))
        {
            try{
                new-item -ItemType Directory -Path $installPath -Force
            }catch{
                throw 'Unable to create installPath'
            }
            
        }
        
        write-verbose 'Uncompressing zip'
        try{
            Expand-Archive -Path $tempPath -DestinationPath $installPath -Force
        }catch{
            throw 'Unable to expand archive'
        }
       
        write-verbose 'Installation Complete'
    }
    end{
        if(test-path $tempPath)
        {
            write-verbose 'Removing zip file'
            try{
                remove-item $tempPath -Force
                write-verbose 'Zip file removed'
            }catch{
                write-warning 'Unable to remove the ffmpeg zip file'
            }
        }
        
    }
    
}

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


#Since libx264 needs easily divisible numbers,
#Make a function that finds the nearest even number
function get-EvenNumber
{
    Param(
    [int]$number
    )
    if($($number/2) -like '*.5')
    {
        $number = $number-1
    }
    return $number
}

function get-screenScaling
{

    <#
        .SYNOPSIS
            get the screen scale
            
        .DESCRIPTION
            get the screen scale
            
            
        .NOTES
            Author: Adrian Andersson
            Last-Edit-Date: 2019-03-15
            
            
            Changelog:

                2019-03-15 - AA
                    - Initial Script
                    - TypeDefinitiion from here:
                        - https://hinchley.net/articles/get-the-scaling-rate-of-a-display-using-powershell/

                2019-03-17 - AA
                    - Fixing bugs
                        - Thanks to lazytao for raising this
                    
        .COMPONENT
            What cmdlet does this script live in
    #>

    [CmdletBinding()]
    PARAM(
        
    )
    begin{
        #Return the script name when running verbose, makes it tidier
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        #Return the sent variables when running debug
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"



        $typeDefinition = @(
            'using System;',
            'using System.Runtime.InteropServices;',
            'using System.Drawing;',
            '',
            'public class DPI {',
            '   [DllImport("gdi32.dll")]',
            '   static extern int GetDeviceCaps(IntPtr hdc, int nIndex);',
            '',
            '   public enum DeviceCap {',
            '       VERTRES = 10,',
            '       DESKTOPVERTRES = 117',
            '   } ',
            '',
            '   public static float scaling() {',
            '       Graphics g = Graphics.FromHwnd(IntPtr.Zero);',
            '       IntPtr desktop = g.GetHdc();',
            '       int LogicalScreenHeight = GetDeviceCaps(desktop, (int)DeviceCap.VERTRES);',
            '       int PhysicalScreenHeight = GetDeviceCaps(desktop, (int)DeviceCap.DESKTOPVERTRES);',
            '       return (float)PhysicalScreenHeight / (float)LogicalScreenHeight;',
            '   }',
            '}'
        )

        

        
        
    }
    
    process{

        
        try{
            write-verbose 'Getting DPI 1st Attempt'
            $dpi = [dpi]::scaling()

        }catch{
            write-verbose 'Typedef missing, adding'
            Add-Type $($typeDefinition -join "`n") -ReferencedAssemblies 'System.Drawing.dll'
            write-verbose 'Getting DPI 2nd Attempt'
            $dpi = [dpi]::scaling()
        }

        if(!$dpi -or ($dpi -le 0))
        {
            throw 'unable to get screen DPI'
        }else{
            write-verbose 'Got screen dpi'

            $dpi
        }
        
        
    }
    
}

function Out-screenshot
{
    param(
        [int]$verStart,
        [int]$horStart,
        [int]$verEnd,
        [int]$horEnd,
        [string]$path,
        [switch]$captureCursor
    )
    $bounds = [drawing.rectangle]::FromLTRB($horStart,$verStart,$horEnd,$verEnd)
    $jpg = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.height
    $graphics = [drawing.graphics]::FromImage($jpg)
    $graphics.CopyFromScreen($bounds.Location,[Drawing.Point]::Empty,$bounds.Size)
    if($captureCursor)
    {
        write-verbose "CaptureCursor is true"
        $scale = get-screenScaling
        $mousePos = [System.Windows.Forms.Cursor]::Position
        $mouseX = $mousePos.x * $scale
        $mouseY = $mousePos.y * $scale
        if(($mouseX -gt $horStart)-and($mouseX -lt $horEnd)-and($mouseY -gt $verStart) -and ($mouseY -lt $verEnd))
        {
            write-verbose "Mouse is in the box"
            #Get the position in the box
            $x = $mouseX - $horStart
            $y = $mouseY - $verStart
            write-verbose "X: $x, Y: $y"
            #Add a 4 pixel red-dot
            $pen = [drawing.pen]::new([drawing.color]::Red)
            $pen.width = 5
            $pen.LineJoin = [Drawing.Drawing2D.LineJoin]::Bevel
            #$hand = [System.Drawing.SystemIcons]::Hand
            #$arrow = [System.Windows.Forms.Cursors]::Arrow
            #$graphics.DrawIcon($arrow, $x, $y)
            $graphics.DrawRectangle($pen,$x,$y, 5,5)
            #$mousePos
        }
    }
    $jpg.Save($path,"JPEG")
}

