#global fileprivate // swc-option sema-only
#global skip
#test
{
    var t = 0
    foreach i in [4, 5]
    {
        t += i
    }
    @assert(t == 9)
}
