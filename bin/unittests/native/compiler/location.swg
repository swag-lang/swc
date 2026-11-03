#global private
const MarkerValue = 0

func markerFunction()->s32
{
    return 42
}

const MarkerLocation   = #location(MarkerValue)
const FunctionLocation = #location(markerFunction)

#assert(MarkerLocation.fileName != null)
#assert(MarkerLocation.lineStart > 0)
#assert(MarkerLocation.lineEnd >= MarkerLocation.lineStart)
#assert(FunctionLocation.fileName == MarkerLocation.fileName)
#assert(FunctionLocation.lineStart > MarkerLocation.lineStart)

// #location matches at compile and runtime
#test
{
    const localMarker = #location(MarkerValue)
    Swag.require(localMarker.fileName == MarkerLocation.fileName)
    Swag.require(localMarker.lineStart == MarkerLocation.lineStart)
    Swag.require(localMarker.lineEnd == MarkerLocation.lineEnd)
    Swag.require(FunctionLocation.lineStart > MarkerLocation.lineStart)
    Swag.require(markerFunction() == 42)
}
