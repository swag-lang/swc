#global internal

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
