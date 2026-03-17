#global fileprivate // swc-option sema-only
#global skip
var G: s32

#test
{
    #ast
    {
        return #"G = 666"#
    }

    @assert(G == 666)
}
