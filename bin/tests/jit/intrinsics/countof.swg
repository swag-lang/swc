#global fileprivate

enum Color
{
    Red
    Green
    Blue
    Alpha
}

struct CountedRuntime
{
    count: u64
}

struct ZeroSized
{
}

enum RefCountKind
{
    A
    B
    C
    D
}

struct RefCountedRuntime
{
    count: u64
}

impl CountedRuntime
{
    mtd opCount() => me.count
}

impl RefCountedRuntime
{
    mtd opCount() => me.count
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
    func countCString(value: cstring)->u64 { return @countof(value) }
    const V0 = #run countCString(cast(cstring) @dataof("runtime"))
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

#test
{
    func countArray(value: [5] u16)->u64 { return @countof(value) }
    const V0 = #run countArray([1'u16, 2'u16, 3'u16, 4'u16, 5'u16])
    #assert(V0 == 5'u64)
}

#test
{
    func countAny(values: ...)->u64 { return @countof(values) }
    const V0 = #run countAny(1, "ab", true, 4.0'f64)
    #assert(V0 == 4'u64)
}

#test
{
    func countStruct(value: CountedRuntime)->u64 { return @countof(value) }
    const V0 = #run countStruct({7})
    const V1 = #run countStruct({0})
    #assert(V0 == 7'u64)
    #assert(V1 == 0'u64)
}

#test
{
    func countZeroSizedSlice()->u64
    {
        var values: [3] ZeroSized
        let slice = cast([..] ZeroSized) values
        return @countof(slice)
    }

    const V0 = #run countZeroSizedSlice()
    #assert(V0 == 3'u64)
}

#test
{
    func countStringRef()->u64
    {
        var text = "hello"
        var textRef: &string = &text
        return @countof(textRef)
    }

    func loopStringRef()->u64
    {
        var text = "hello"
        let textRef: const &string = &text
        var count: u64 = 0
        for textRef do
            count += 1
        return count
    }

    const V0 = #run countStringRef()
    const V1 = #run loopStringRef()
    #assert(V0 == 5'u64)
    #assert(V1 == 5'u64)
}

#test
{
    func countCStringRef()->u64
    {
        var value: cstring = cast(cstring) @dataof("abcd")
        var valueRef: &cstring = &value
        return @countof(valueRef)
    }

    func loopCStringRef()->u64
    {
        var value: cstring = cast(cstring) @dataof("abcd")
        let valueRef: &cstring = &value
        var count: u64 = 0
        for valueRef do
            count += 1
        return count
    }

    const V0 = #run countCStringRef()
    const V1 = #run loopCStringRef()
    #assert(V0 == 4'u64)
    #assert(V1 == 4'u64)
}

#test
{
    func countArrayAndSliceRef()->u64
    {
        var array: [2, 3] u8
        var arrayRef: &[2, 3] u8 = &array

        var flat: [6] u8 = [1, 2, 3, 4, 5, 6]
        let slice = cast([..] u8) flat
        let sliceRef: const &[..] u8 = &slice
        return @countof(arrayRef) + @countof(sliceRef)
    }

    func loopSliceRef()->u64
    {
        var flat: [6] u8 = [1, 2, 3, 4, 5, 6]
        let slice = cast([..] u8) flat
        let sliceRef: const &[..] u8 = &slice
        var count: u64 = 0
        for sliceRef do
            count += 1
        return count
    }

    const V0 = #run countArrayAndSliceRef()
    const V1 = #run loopSliceRef()
    #assert(V0 == 12'u64)
    #assert(V1 == 6'u64)
}

#test
{
    func countUnsignedRef()->u32
    {
        var value: u32 = 7
        var valueRef: &u32 = &value
        return @countof(valueRef)
    }

    func loopUnsignedRef()->u32
    {
        var value: u32 = 7
        let valueRef: &u32 = &value
        var count: u32 = 0
        for valueRef do
            count += 1
        return count
    }

    const V0 = #run countUnsignedRef()
    const V1 = #run loopUnsignedRef()
    #assert(#typeof(V0) == u32)
    #assert(V0 == 7'u32)
    #assert(V1 == 7'u32)
}

#test
{
    func countEnumRef()->u64
    {
        var kind = RefCountKind.C
        var kindRef: &RefCountKind = &kind
        return @countof(kindRef)
    }

    func countSpecRef()->u64
    {
        let value = RefCountedRuntime{count: 11}
        let valueRef: const &RefCountedRuntime = &value
        return @countof(valueRef)
    }

    const V0 = #run countEnumRef()
    const V1 = #run countSpecRef()
    #assert(V0 == 4'u64)
    #assert(V1 == 11'u64)
}
