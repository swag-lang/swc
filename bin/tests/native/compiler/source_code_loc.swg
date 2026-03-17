#global fileprivate // 

#test
{
    var a: Swag.SourceCodeLocation
    @assert(a.fileName == null)
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
    @assert(c.fileName != null)
}

#test
{
    const L = #curlocation
    #assert(L.fileName == A.fileName)
    #assert(L.lineStart > B.lineStart)
    @assert(L.fileName == A.fileName)
}
