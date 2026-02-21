#global internal

enum Color
{
    Red
    Green
    Blue
    Alpha
}

#test
{
    func countEnum()->u64 { return @countof(Color) }
    const V0 = #run countEnum()
    #assert(V0 == 4'u64)
}

#test
{
    func countString(value: string)->u64 { return @countof(value) }
    const V0 = #run countString("runtime")
    #assert(V0 == 7'u64)
}

#test
{
    func countSlice(value: [..] u8)->u64 { return @countof(value) }

    const data: [6] u8 = [0, 0, 0, 0, 0, 0]
    const V0 = #run countSlice(cast([..] u8) data)
    #assert(V0 == 6'u64)
}

#test
{
    func countTypedVariadic(values: s32...)->u64 { return @countof(values) }
    const V0 = #run countTypedVariadic(1, 2, 3, 4, 5)
    #assert(V0 == 5'u64)
}

#test
{
    func countTypedVariadicWithHead(head: s32, values: s32...)->u64 { return @countof(values) }
    const V0 = #run countTypedVariadicWithHead(10, 20, 30, 40)
    #assert(V0 == 3'u64)
}

#test
{
    func countUnsigned32(value: u32)->u32 { return @countof(value) }
    const V0 = #run countUnsigned32(42'u32)
    #assert(#typeof(V0) == u32)
    #assert(V0 == 42'u32)
}

#test
{
    func countUnsigned64(value: u64)->u64 { return @countof(value) }
    const V0 = #run countUnsigned64(1000'u64)
    #assert(#typeof(V0) == u64)
    #assert(V0 == 1000'u64)
}
