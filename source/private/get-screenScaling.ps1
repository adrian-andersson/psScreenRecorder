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