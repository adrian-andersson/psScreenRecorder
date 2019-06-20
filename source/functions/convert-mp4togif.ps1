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
