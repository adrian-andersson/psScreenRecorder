<#
    Test helper: drives the region selection overlay by posting mouse messages to it, the way Windows would,
    without moving the real mouse.

    Run it in a background runspace (or another process) while the overlay is shown, as the overlay blocks the
    thread that shows it. Note FindWindow gets [NullString]::Value for the title: PowerShell turns $null into
    an empty string, which would only match windows with no title.

    -Gesture Drag    a click without a drag (which should be ignored), then a drag from From to To
    -Gesture Cancel  a right-click

    Coordinates are relative to the overlay, which covers the virtual desktop from its top left corner.
    Returns 'posted' once done, or throws if the overlay never appeared.
#>
param(
    [ValidateSet('Drag','Cancel')]
    [string]$Gesture = 'Drag',
    [int[]]$From = @(100,50),
    [int[]]$To = @(500,350),
    [int]$TimeoutSeconds = 30
)

if(!('PsScreenRecorderTest.Input' -as [type]))
{
    Add-Type -Namespace PsScreenRecorderTest -Name Input -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string className, string windowName);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
'@
}

$window = [IntPtr]::Zero
$deadline = [datetime]::Now.AddSeconds($TimeoutSeconds)
while($window -eq [IntPtr]::Zero -and [datetime]::Now -lt $deadline)
{
    Start-Sleep -Milliseconds 100
    $window = [PsScreenRecorderTest.Input]::FindWindow('PsScreenRecorderRegionSelector', [NullString]::Value)
}
if($window -eq [IntPtr]::Zero){ throw 'The overlay never appeared' }
Start-Sleep -Milliseconds 300

$post = {
    param([uint32]$Message, [int]$X, [int]$Y)
    $position = [IntPtr](($Y -shl 16) -bor ($X -band 0xFFFF))
    $null = [PsScreenRecorderTest.Input]::PostMessage($window, $Message, [IntPtr]::Zero, $position)
    Start-Sleep -Milliseconds 60
}
if($Gesture -eq 'Cancel')
{
    & $post 0x0204 $From[0] $From[1]
    return 'posted'
}
#A click without a drag, which the overlay should ignore
& $post 0x0201 $From[0] $From[1]
& $post 0x0202 ($From[0] + 1) ($From[1] + 1)
#Then a real drag
& $post 0x0201 $From[0] $From[1]
& $post 0x0200 ([int](($From[0] + $To[0]) / 2)) ([int](($From[1] + $To[1]) / 2))
& $post 0x0200 $To[0] $To[1]
& $post 0x0202 $To[0] $To[1]
'posted'
