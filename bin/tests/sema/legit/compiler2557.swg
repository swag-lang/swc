#global fileprivate // swc-option sema-only
#global skip
//#global testerror

func toto()
{
    #if false do
        alias AA = s32
    #else do
        alias AA = s64
    var x: AA
    @assert(#typeof(x) == s64)
}

#test
{
    toto()
}
