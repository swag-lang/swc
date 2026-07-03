#global private

func semaTest001()
{
    var a: Swag.SourceCodeLocation
}

const A = #curlocation
#assert(A.lineStart == 8)
#assert(A.colStart == 11)
#assert(A.fileName != null)

const B = #curlocation
#assert(B.lineStart > A.lineStart)
#assert(B.colStart == 11)
#assert(B.fileName == A.fileName)

func semaTest002()
{
    var c: Swag.SourceCodeLocation = #curlocation
    @assert(c.fileName != null)
}

func semaTest003()
{
    const L = #curlocation
    #assert(L.fileName == A.fileName)
    #assert(L.lineStart > B.lineStart)
}

func statementRunCurLocation()
{
    #run
    {
        #assert(#curlocation.funcName == #location(statementRunCurLocation).funcName)
    }
}

#[Swag.Inline]
func inlineCaptureLoc(loc = #callerlocation)->Swag.SourceCodeLocation => loc

#[Swag.Inline]
func inlineCallerLoc()->Swag.SourceCodeLocation
{
    return inlineCaptureLoc()
}

const InlineCallerDecl = #location(inlineCallerLoc)

func semaTest004()
{
    let loc = inlineCallerLoc()
    @assert(loc.fileName == A.fileName)
    @assert(loc.funcName != null)
    @assert(loc.funcName == InlineCallerDecl.funcName)
    @assert(loc.lineStart == 37)
    @assert(loc.colStart == 12)
}
