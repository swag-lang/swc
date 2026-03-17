#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x: s32 = 666
    var y  = dref &x
    @assert(x == 666)
}
