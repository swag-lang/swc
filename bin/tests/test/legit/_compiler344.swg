// swc-option suite-test

#global fileprivate

#test
{
    var a: s32
    @assert(a == 0)
    var b: *s32
    @assert(b == null)
}
