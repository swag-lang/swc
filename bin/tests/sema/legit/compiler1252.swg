#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x, y: s32
    x, y = 10
    @assert(x == 10)
    @assert(y == 10)
}
