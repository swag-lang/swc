#global private

#test
{
    var a: Swag.SourceCodeLocation
    Swag.assert(a.fileName == null)
}

const A = #curlocation
#assert(A.lineStart == 9)
#assert(A.colStart == 11)
#assert(A.fileName != null)

const B = #curlocation
#assert(B.lineStart > A.lineStart)
#assert(B.colStart == 11)
#assert(B.fileName == A.fileName)

#test
{
    var c: Swag.SourceCodeLocation = #curlocation
    Swag.assert(c.fileName != null)
}

#test
{
    const L = #curlocation
    #assert(L.fileName == A.fileName)
    #assert(L.lineStart > B.lineStart)
    Swag.assert(L.fileName == A.fileName)
}

func nativeCaptureLoc(loc = #callerlocation)->Swag.SourceCodeLocation => loc

func nativeCallerLoc()->Swag.SourceCodeLocation
{
    return nativeCaptureLoc()
}

#test
{
    let loc = nativeCallerLoc()
    Swag.assert(loc.fileName != null)
    Swag.assert(loc.funcName != null)
    Swag.assert(loc.lineStart == 37)
    Swag.assert(loc.colStart == 12)
}
