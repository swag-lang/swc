#global fileprivate

func typeofMixedArrayLiteral()->bool
{
    #assert(#typeof([1, 2.5]) == const [2] f32)
    let values = [1, 2.5]
    let idx = 1
    return values[0] == 1.0'f32 and values[idx] == 2.5'f32
}

func typeofWideArrayLiteral()->bool
{
    #assert(#typeof([1, 5_000_000_000]) == const [2] s64)
    let values = [1, 5_000_000_000]
    let idx = 1
    return values[0] == 1's64 and values[idx] == 5_000_000_000's64
}

#test
{
    const mixedOk = #run typeofMixedArrayLiteral()
    const wideOk  = #run typeofWideArrayLiteral()
    #assert(mixedOk)
    #assert(wideOk)
}
