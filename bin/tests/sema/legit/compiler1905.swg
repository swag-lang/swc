#global fileprivate // swc-option sema-only
#global skip
#test
{
    let ptr = #typeof(s32)
    var g   = 0
    switch ptr
    {
    case s32:
        g = 1
    default:
        @assert(false)
    }

    @assert(g == 1)
}
