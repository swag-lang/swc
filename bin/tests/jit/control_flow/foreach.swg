#global fileprivate

struct ForeachVariadicPayload
{
    arr: [3] s32
    flag: bool
    tag: u8
}

#test
{
    func foreachArrayValueIndex()->s32
    {
        var arr: [5] s32 = [1, 2, 3, 4, 5]
        var acc: s32 = 0

        foreach v, i in arr
        {
            acc += v + cast(s32) i
        }

        return acc
    }

    const V = #run foreachArrayValueIndex()
    #assert(V == 25)
}

#test
{
    func foreachWhereControl()->s32
    {
        var arr: [8] s32 = [1, 2, 3, 4, 5, 6, 7, 8]
        var acc: s32 = 0

        foreach v in arr where (v & 1) == 0
        {
            if v == 6
            {
                continue
            }
            if v == 8
            {
                break
            }
            acc += v
        }

        return acc
    }

    const V = #run foreachWhereControl()
    #assert(V == 6)
}

#test
{
    func foreachByAddressRead()->s32
    {
        var arr: [4] s32 = [1, 2, 3, 4]
        var sum: s32 = 0

        foreach &v, i in arr
        {
            sum += dref v + cast(s32) i
        }

        return sum
    }

    const V = #run foreachByAddressRead()
    #assert(V == 16)
}

#test
{
    func foreachNoAlias()->u64
    {
        var arr: [3] s32 = [11, 22, 33]
        var count: u64 = 0

        foreach arr
        {
            count += 1
        }

        return count
    }

    const V = #run foreachNoAlias()
    #assert(V == 3)
}

#test
{
    func foreachStringValueIndex()->u32
    {
        var text: string = "ABC"
        var acc: u32 = 0

        foreach v, i in text
        {
            acc += cast(u32) v + cast(u32) i
        }

        return acc
    }

    const V = #run foreachStringValueIndex()
    #assert(V == 201'u32)
}

#test
{
    func foreachSliceValueIndex()->s32
    {
        var arr: [4] s32 = [5, 6, 7, 8]
        var sl = cast([..] s32) arr
        var acc: s32 = 0

        foreach v, i in sl
        {
            acc += v + cast(s32) i
        }

        return acc
    }

    const V = #run foreachSliceValueIndex()
    #assert(V == 32)
}

#test
{
    func foreachSliceWeighted()->s32
    {
        var arr: [4] s32 = [5, 6, 7, 8]
        var sl = cast([..] s32) arr
        var acc: s32 = 0
        foreach v, i in sl
        {
            acc += v * cast(s32) (i + 1)
        }

        return acc
    }

    const V = #run foreachSliceWeighted()
    #assert(V == 70)
}

#test
{
    func foreachUntypedVariadic(values: ...)->s32
    {
        var acc: s32 = 0

        foreach v, i in values
        {
            let p = cast(*s32) @dataof(v)
            acc += dref p + cast(s32) i
        }

        return acc
    }

    const V = #run foreachUntypedVariadic(3's32, 4's32, 5's32)
    #assert(V == 15)
}

#test
{
    func foreachTypedVariadic(values: s32...)->s32
    {
        var acc: s32 = 0

        foreach v, i in values
        {
            acc += v * cast(s32) (i + 1)
        }

        return acc
    }

    const V = #run foreachTypedVariadic(2, 3, 4)
    #assert(V == 20)
}

#test
{
    func foreachTypedVariadicPayload(values: ForeachVariadicPayload...)->u64
    {
        var acc: u64 = 0

        foreach v, i in values
        {
            acc += cast(u64) v.arr[0] + cast(u64) v.arr[2] + cast(u64) v.flag + cast(u64) v.tag + i
        }

        return acc
    }

    const p0: ForeachVariadicPayload = {arr: [7, 8, 9], flag: true, tag: 2'u8}
    const p1: ForeachVariadicPayload = {arr: [1, 2, 3], flag: false, tag: 4'u8}
    const V = #run foreachTypedVariadicPayload(p0, p1)
    #assert(V == 28'u64)
}

#test
{
    func foreachNestedWithWhere(values: s32...)->s32
    {
        var acc: s32 = 0

        foreach v, i in values where (v & 1) == 1
        {
            foreach w, j in values
            {
                if j == i do
                    continue
                acc += v + w + cast(s32) i + cast(s32) j
            }
        }

        return acc
    }

    const V = #run foreachNestedWithWhere(1, 2, 3, 4, 5)
    #assert(V == 120)
}

#test
{
    func foreachUntypedMixed(values: ...)->s32
    {
        var acc: s32 = 0

        foreach v, i in values
        {
            if @kindof(v) == s32
            {
                let p = cast(*s32) @dataof(v)
                acc += dref p * cast(s32) (i + 1)
                continue
            }

            if @kindof(v) == bool
            {
                let p = cast(*bool) @dataof(v)
                acc += cast(s32) dref p * 10
                continue
            }

            if @kindof(v) == rune
            {
                let p = cast(*rune) @dataof(v)
                acc += cast(s32) dref p
            }
        }

        return acc
    }

    const V = #run foreachUntypedMixed(2's32, true, cast(rune) 'A', 4's32, false)
    #assert(V == 93)
}

#test
{
    func foreachTypedLarge(values: s32...)->s32
    {
        var acc: s32 = 0

        foreach v, i in values
        {
            if (i & 1) == 0
            {
                acc += v * cast(s32) (i + 1)
            }
            else
            {
                acc -= v * cast(s32) (i + 1)
            }
        }

        return acc
    }

    const V = #run foreachTypedLarge(10, 9, 8, 7, 6, 5, 4, 3, 2, 1)
    #assert(V == 0)
}
