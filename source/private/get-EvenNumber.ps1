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