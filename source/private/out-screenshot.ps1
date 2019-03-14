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
        $mousePos = [System.Windows.Forms.Cursor]::Position
        if(($mousePos.x -gt $horStart)-and($mousepos.x -lt $horEnd)-and($mousePos.y -gt $verStart) -and ($mousePos.y -lt $verEnd))
        {
            write-verbose "Mouse is in the box"
            #Get the position in the box
            $x = $mousePos.x - $horStart
            $y = $mousePos.y - $verStart
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