#global fileprivate

const A = 0

func semaTest001()
{
    const L = #location(A)
    #assert(L.fileName != null)
    #assert(L.lineStart == 3)
}
