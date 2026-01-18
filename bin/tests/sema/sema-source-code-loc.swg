#global internal

#test
{
    var a: Swag.SourceCodeLocation
}

const A = #curlocation
#assert(A.lineStart == 8)
#assert(A.colStart == 11)
//#print(A.fileName)