#global fileprivate // swc-option sema-only
#global skip
struct(T, N: u8) A
{
    x:     [N] T
    y:     u32
}

#test
{
    var x: A'(s32, 5)
    @assert(#sizeof(x) == 6 * #sizeof(s32))
    //@print(#typeof(x.y).name)
}
