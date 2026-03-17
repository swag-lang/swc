#global fileprivate // swc-option sema-only
#global skip
#test
{
    test()
}

func test(x = #callerlocation)
{
    //@print(x.fileName)
    @assert(x.lineStart == 2)
    @assert(x.lineEnd == 2)
    @assert(x.colStart == 4)
}
