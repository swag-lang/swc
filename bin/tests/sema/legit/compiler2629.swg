#global fileprivate // swc-option sema-only
#global skip
#if false
{
    var G = 0
    var H = 1
}
#else
{
    var G = 1
}

#assert(#defined(G))
#assert(!#defined(H))

#test
{
    @assert(G == 1)
}
