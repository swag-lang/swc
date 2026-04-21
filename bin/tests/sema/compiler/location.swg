#global fileprivate

const A = 0

#test
{
    const L = #location(A)
    #assert(L.fileName != null)
    #assert(L.lineStart == 3)
}
