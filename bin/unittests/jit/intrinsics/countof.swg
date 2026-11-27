#global private

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

struct ZeroSized {}

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
    func countEnum()->u64 { return Color.count }
    const V0 = #run countEnum()
    #assert(V0 == 4_u64)
}

#test
{
    func countString(value: string)->u64 { return value.count }
    const V0 = #run countString("runtime")
    #assert(V0 == 7_u64)
}

#test
{
    func countCString(value: const cstring)->u64 { return value.count }
    const V0 = #run countCString(cast(const cstring, ("runtime").buffer))
    #assert(V0 == 7_u64)
}

#test
{
    func countSlice(value: const [..] u8)->u64 { return value.count }

    const data: [6] u8 = [0, 0, 0, 0, 0, 0]
    const V0 = #run countSlice(cast(const [..] u8, data))
    #assert(V0 == 6_u64)
}

#test
{
    func countTypedVariadic(values: s32...)->u64 { return values.count }
    const V0 = #run countTypedVariadic(1, 2, 3, 4, 5)
    #assert(V0 == 5_u64)
}

#test
{
    func countTypedVariadicWithHead(_: s32, values: s32...)->u64 { return values.count }
    const V0 = #run countTypedVariadicWithHead(10, 20, 30, 40)
    #assert(V0 == 3_u64)
}

#test
{
    func countUnsigned32(value: u32)->u32 { return value.count }
    const V0 = #run countUnsigned32(42_u32)
    #assert(#typeof(V0) == u32)
    #assert(V0 == 42_u32)
}

#test
{
    func countSigned32(value: s32)->s32 { return value.count }
    const V0 = #run countSigned32(42_s32)
    #assert(#typeof(V0) == s32)
    #assert(V0 == 42_s32)
}

#test
{
    func countUnsigned64(value: u64)->u64 { return value.count }
    const V0 = #run countUnsigned64(1000_u64)
    #assert(#typeof(V0) == u64)
    #assert(V0 == 1000_u64)
}

#test
{
    func countArray(value: [5] u16)->u64 { return value.count }
    const V0 = #run countArray([1_u16, 2_u16, 3_u16, 4_u16, 5_u16])
    #assert(V0 == 5_u64)
}

#test
{
    func countAny(values: ...)->u64 { return values.count }
    const V0 = #run countAny(1, "ab", true, 4.0_f64)
    #assert(V0 == 4_u64)
}

#test
{
    func countStruct(value: CountedRuntime)->u64 { return value.count }
    const V0 = #run countStruct(CountedRuntime{7})
    const V1 = #run countStruct(CountedRuntime{0})
    #assert(V0 == 7_u64)
    #assert(V1 == 0_u64)
}

#test
{
    const V0 = #run (3_s8).count
    const V1 = #run (4_s32).count
    const V2 = #run (5_s64).count
    #assert(#typeof(V0) == s8)
    #assert(#typeof(V1) == s32)
    #assert(#typeof(V2) == s64)
    #assert(V0 == 3_s8)
    #assert(V1 == 4_s32)
    #assert(V2 == 5_s64)
}

#test
{
    func countZeroSizedSlice()->u64
    {
        var values: [3] ZeroSized
        let slice = cast([..] ZeroSized, values)
        return slice.count
    }

    const V0 = #run countZeroSizedSlice()
    #assert(V0 == 3_u64)
}

#test
{
    func countStringRef()->u64
    {
        var text = "hello"
        var textRef: *string = &text
        return (textRef[]).count
    }

    func loopStringRef()->u64
    {
        var text         = "hello"
        let textRef: const *string = &text
        var count:   u64 = 0
        for textRef[]
        {
            count += 1
        }
        return count
    }

    const V0 = #run countStringRef()
    const V1 = #run loopStringRef()
    #assert(V0 == 5_u64)
    #assert(V1 == 5_u64)
}

#test
{
    func countCStringRef()->u64
    {
        var valueData: [5] u8   = ['a'_u8, 'b'_u8, 'c'_u8, 'd'_u8, 0]
        var value:     cstring  = cast(cstring, &valueData[0])
        var valueRef:  *cstring = &value
        return (valueRef[]).count
    }

    func loopCStringRef()->u64
    {
        var valueData: [5] u8   = ['a'_u8, 'b'_u8, 'c'_u8, 'd'_u8, 0]
        var value:     cstring  = cast(cstring, &valueData[0])
        let valueRef:  *cstring = &value
        var count:     u64      = 0
        for valueRef[]
        {
            count += 1
        }
        return count
    }

    const V0 = #run countCStringRef()
    const V1 = #run loopCStringRef()
    #assert(V0 == 4_u64)
    #assert(V1 == 4_u64)
}

#test
{
    func countArrayAndSliceRef()->u64
    {
        var array:    [2, 3] u8
        var arrayRef: *[2, 3] u8 = &array

        var flat:     [6] u8         = [1, 2, 3, 4, 5, 6]
        let slice = cast([..] u8, flat)
        let sliceRef: const *[..] u8 = &slice
        return (arrayRef[]).count + (sliceRef[]).count
    }

    func loopSliceRef()->u64
    {
        var flat:     [6] u8         = [1, 2, 3, 4, 5, 6]
        let slice                    = cast([..] u8, flat)
        let sliceRef: const *[..] u8 = &slice
        var count:    u64            = 0
        for sliceRef[]
        {
            count += 1
        }
        return count
    }

    const V0 = #run countArrayAndSliceRef()
    const V1 = #run loopSliceRef()
    #assert(V0 == 12_u64)
    #assert(V1 == 6_u64)
}

#test
{
    func countUnsignedRef()->u32
    {
        var value:    u32  = 7
        var valueRef: *u32 = &value
        return (valueRef[]).count
    }

    func loopUnsignedRef()->u32
    {
        var value:    u32  = 7
        let valueRef: *u32 = &value
        var count:    u32  = 0
        for valueRef[]
        {
            count += 1
        }
        return count
    }

    const V0 = #run countUnsignedRef()
    const V1 = #run loopUnsignedRef()
    #assert(#typeof(V0) == u32)
    #assert(V0 == 7_u32)
    #assert(V1 == 7_u32)
}

#test
{
    func countSignedRef()->s32
    {
        var value:    s32  = 7
        var valueRef: *s32 = &value
        return (valueRef[]).count
    }

    func loopSignedRef()->s32
    {
        var value:    s32  = 7
        let valueRef: *s32 = &value
        var count:    s32  = 0
        for valueRef[]
        {
            count += 1
        }
        return count
    }

    const V0 = #run countSignedRef()
    const V1 = #run loopSignedRef()
    #assert(#typeof(V0) == s32)
    #assert(V0 == 7_s32)
    #assert(V1 == 7_s32)
}

#test
{
    func countEnumRef()->u64
    {
        var kind = RefCountKind.C
        var kindRef: *RefCountKind = &kind
        return (kindRef[]).count
    }

    func countSpecRef()->u64
    {
        let value = RefCountedRuntime{count: 11}
        let valueRef: const *RefCountedRuntime = &value
        return (valueRef[]).count
    }

    const V0 = #run countEnumRef()
    const V1 = #run countSpecRef()
    #assert(V0 == 4_u64)
    #assert(V1 == 11_u64)
}
