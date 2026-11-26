#global private

#[Swag.Inline]
func inlineDivInterleavedShift(a: u32, b: u32, c: u32)->u32
{
    var q:  u32 = a / b
    var s:  u32 = c >> q
    var q2: u32 = c / b
    var s2: u32 = a << (q - 1_u32)
    return s + q + q2 + s2
}

#test
{
    const V = #run inlineDivInterleavedShift(24_u32, 6_u32, 128_u32)
    #assert(#typeof(V) == u32)
    #assert(V == 225_u32)
}
