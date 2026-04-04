#global fileprivate

#test
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

#test
{
    var c: Swag.SourceCodeLocation = #curlocation
    @assert(c.fileName != null)
}

#test
{
    const L = #curlocation
    #assert(L.fileName == A.fileName)
    #assert(L.lineStart > B.lineStart)
}

#[Swag.Inline]
func inlineCaptureLoc(loc = #callerlocation)->Swag.SourceCodeLocation => loc

#[Swag.Inline]
func inlineCallerLoc()->Swag.SourceCodeLocation
{
    return inlineCaptureLoc()
}

const InlineCallerDecl = #location(inlineCallerLoc)

#test
{
    let loc = inlineCallerLoc()
    @assert(loc.fileName == A.fileName)
    @assert(loc.funcName != null)
    @assert(loc.funcName == InlineCallerDecl.funcName)
    @assert(loc.lineStart == 37)
    @assert(loc.colStart == 12)
}

#test { const bad = #callerlocation } // swc-expected-error {{sema_err_caller_location_default_only}}
