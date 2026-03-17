#global fileprivate // 

const MarkerValue = 0

func markerFunction()->s32
{
    return 42
}

const MarkerLocation = #location(MarkerValue)
const FunctionLocation = #location(markerFunction)

#assert(MarkerLocation.fileName != null)
#assert(MarkerLocation.lineStart > 0)
#assert(MarkerLocation.lineEnd >= MarkerLocation.lineStart)
#assert(FunctionLocation.fileName == MarkerLocation.fileName)
#assert(FunctionLocation.lineStart > MarkerLocation.lineStart)

#test
{
    const localMarker = #location(MarkerValue)
    @assert(localMarker.fileName == MarkerLocation.fileName)
    @assert(localMarker.lineStart == MarkerLocation.lineStart)
    @assert(localMarker.lineEnd == MarkerLocation.lineEnd)
    @assert(FunctionLocation.lineStart > MarkerLocation.lineStart)
    @assert(markerFunction() == 42)
}
