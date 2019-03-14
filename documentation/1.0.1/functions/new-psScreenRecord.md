---
external help file: psScreenRecorder-help.xml
Module Name: psScreenRecorder
online version:
schema: 2.0.0
---

# new-psScreenRecord

## SYNOPSIS
Simple Screen-Capture done in PowerShell

      Needs ffmpeg: https://www.ffmpeg.org/

## SYNTAX

```
new-psScreenRecord [[-outFolder] <String>] [[-fps] <String>] [[-videoName] <String>] [[-ffMPegPath] <String>]
 [-Confirm] [-leaveImages] [<CommonParameters>]
```

## DESCRIPTION
Simple Screen-Capture done in PowerShell.
      Useful for making tutorial  and demonstration videos

      Also draws a big red dot where your cursor is, if it is in the defined window bounds

      Uses FFMPeg to make a video file
      Video file can then be edited in your fav video editor
      Like Blender :)


      You will need to download and setup FFMPEG first

      https://www.ffmpeg.org/

      The default path to the ffmpeg exe is c:\program files\ffmpeg\bin

## EXAMPLES

### EXAMPLE 1
```
new-psVideoCapture -outFolder 'C:\temp\testVid' -Verbose
```

DESCRIPTION
------------
Will create a new video file with 'out.mp4' filename in c:\temp\testVid folder


OUTPUT
------------
N/A

## PARAMETERS

### -outFolder
The folder to 
          a) Temporarily keep the jpegs
          b) Save the mpeg file

          Is Mandatory

```yaml
Type: String
Parameter Sets: (All)
Aliases: path

Required: False
Position: 1
Default value: C:\temp\ffmpeg\out
Accept pipeline input: False
Accept wildcard characters: False
```

### -fps
{{Fill fps Description}}

```yaml
Type: String
Parameter Sets: (All)
Aliases: framerate

Required: False
Position: 2
Default value: 24
Accept pipeline input: False
Accept wildcard characters: False
```

### -videoName
Name + Extension to output the video file as
      By default will use out.mp4

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: Out.mp4
Accept pipeline input: False
Accept wildcard characters: False
```

### -ffMPegPath
Path to ffMpeg
      Suggest you modify this to be where yours is by default

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: C:\program files\ffmpeg\bin\ffmpeg.exe
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -leaveImages
{{Fill leaveImages Description}}

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable.
For more information, see about_CommonParameters (http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES
Author: Adrian Andersson
Last-Edit-Date: 13-09-2017
	
	
      Changelog
      
          13-09-2017 - AA
              - New script, cleaned-up from an old one I had saved

          14-03-2019 - AA
              - Moved to bartender module

## RELATED LINKS
