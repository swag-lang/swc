#global private

enum ForeachAliasPriority: u32
{
    Low    = 1
    Normal = 5
    High   = 10
}

alias ForeachPriorityAlias       = ForeachAliasPriority

#[Swag.Strict]
alias StrictForeachPriorityAlias = ForeachAliasPriority

#[Swag.Strict]
alias StrictForeachF32           = f32

#test
{
    var arr: [3] s32 = [1, 2, 3]
    var sum          = 0
    for v in arr
    {
        #assert(#typeof(v) == s32)
        var x = v
        sum += x
    }
    Swag.assert(sum == 6)
}

#test
{
    var arr: [2] s32 = [1, 2]
    var sumV         = 0
    var sumI         = 0
    for v, i in arr
    {
        #assert(#typeof(v) == s32)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
        sumV += x
        sumI += cast(s32) y
    }
    Swag.assert(sumV == 3)
    Swag.assert(sumI == 1)
}

#test
{
    var arr: [2] s32 = [1, 2]
    var sum          = 0
    for v in arr where v > 0
    {
        var x = v
        sum += x
    }
    Swag.assert(sum == 3)
}

#test
{
    var arr: [2] u32 = [10'u32, 20]
    for &v in arr
    {
        v[] += 1
    }
    Swag.assert(arr[0] == 11)
    Swag.assert(arr[1] == 21)
}

#test
{
    var text: string = "AB"
    var sumV         = 0
    var sumI         = 0
    for v, i in text
    {
        #assert(#typeof(v) == u8)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
        sumV += cast(s32) x
        sumI += cast(s32) y
    }
    Swag.assert(sumV == cast(s32) 'A'u8 + cast(s32) 'B'u8)
    Swag.assert(sumI == 1)
}

#test
{
    var text: string = "CD"
    var sum          = 0
    for &v in text
    {
        #assert(#typeof(v) == #type const *u8)
        sum += cast(s32) v[]
    }
    Swag.assert(sum == cast(s32) 'C'u8 + cast(s32) 'D'u8)
}

#test
{
    var text: const cstring = cast(const cstring) ("AZ").buffer
    var sumV                = 0
    var sumI: u64
    for v, i in text
    {
        #assert(#typeof(v) == u8)
        #assert(#typeof(i) == u64)
        sumV += cast(s32) v
        sumI += i
    }
    Swag.assert(sumV == cast(s32) 'A'u8 + cast(s32) 'Z'u8)
    Swag.assert(sumI == 1)
}

#test
{
    var text: const cstring = cast(const cstring) ("CD").buffer
    var sum                 = 0
    for &v in text
    {
        #assert(#typeof(v) == #type const *u8)
        sum += cast(s32) v[]
    }
    Swag.assert(sum == cast(s32) 'C'u8 + cast(s32) 'D'u8)
}

#test
{
    var text:  const cstring = cast(const cstring) ("ABC").buffer
    var order: [3] u8
    var pos:   u64
    for v, i in (text).reversed()
    {
        order[pos] = v
        pos        += 1
        Swag.assert(i == 2 - (pos - 1))
    }
    Swag.assert(order[0] == 'C'u8)
    Swag.assert(order[1] == 'B'u8)
    Swag.assert(order[2] == 'A'u8)
}

func foreachCStringRefSum(value: *cstring)->s32
{
    var sum = 0
    for v in value[] do
        sum += cast(s32) v
    return sum
}

#test
{
    var textData: [3] u8  = ['B'u8, 'Y'u8, 0]
    var text:     cstring = cast(cstring) &textData[0]
    Swag.assert(foreachCStringRefSum(&text) == cast(s32) 'B'u8 + cast(s32) 'Y'u8)
}

#test
{
    var arr: [2] s32 = [3, 4]
    var sl           = cast([..] s32) arr
    var sumV         = 0
    var sumI         = 0
    for v, i in sl
    {
        #assert(#typeof(v) == s32)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
        sumV += x
        sumI += cast(s32) y
    }
    Swag.assert(sumV == 7)
    Swag.assert(sumI == 1)
}

#test
{
    func foreachVariadicAny(values: ...)->u64
    {
        var count: u64
        for v, i in values
        {
            #assert(#typeof(v) == any)
            #assert(#typeof(i) == u64)
            var x = v
            var y = i
            count += 1
        }
        return count
    }
    Swag.assert(foreachVariadicAny(1, 2, 3) == 3)
}

#test
{
    func foreachVariadicTyped(values: s32...)->u64
    {
        var count: u64
        for v, i in values
        {
            #assert(#typeof(v) == s32)
            #assert(#typeof(i) == u64)
            var x = v
            var y = i
            count += 1
        }
        return count
    }
    Swag.assert(foreachVariadicTyped(1, 2, 3) == 3)
}

#test
{
    func foreachVariadicAnyErr(values: ...)->u64
    {
        var count: u64
        for v in values
        {
            count += 1
        }
        return count
    }
    Swag.assert(foreachVariadicAnyErr(1, true, "a") == 3)
}

#test
{
    func foreachVariadicTypedErr(values: s32...)->u64
    {
        var count: u64
        for v, i in values
        {
            count += 1
        }
        return count
    }
    Swag.assert(foreachVariadicTypedErr(5, 6) == 2)
}

#test
{
    enum Priority: u32
    {
        Low    = 1
        Normal = 5
        High   = 10
    }

    var sumV: u32
    var sumI: u64
    for value, idx in Priority
    {
        #assert(#typeof(value) == Priority)
        #assert(#typeof(idx) == u64)
        sumV += cast(u32) value
        sumI += idx
    }

    Swag.assert(sumV == 16)
    Swag.assert(sumI == 3)
}

#test
{
    var values: [2] StrictForeachF32 = [cast(StrictForeachF32) 1.5, cast(StrictForeachF32) 2.5]
    var sum:    f32
    for value in values
    {
        #assert(#typeof(value) == StrictForeachF32)
        sum += cast(f32) value
    }

    Swag.assert(sum == 4.0'f32)
}

#test
{
    #[Swag.EnumFlags]
    enum Bits: u32 { A, B, C }

    var mask: u32
    for value in Bits do
        mask |= cast(u32) value

    Swag.assert(mask == 7)
}

#test
{
    var sumV: u32
    var sumI: u64
    for value, idx in ForeachPriorityAlias
    {
        #assert(#typeof(value) == ForeachAliasPriority)
        #assert(#typeof(idx) == u64)
        sumV += cast(u32) value
        sumI += idx
    }

    Swag.assert(sumV == 16)
    Swag.assert(sumI == 3)
}

#test
{
    var sumV: u32
    var sumI: u64
    for value, idx in StrictForeachPriorityAlias
    {
        #assert(#typeof(value) == ForeachAliasPriority)
        #assert(#typeof(idx) == u64)
        sumV += cast(u32) value
        sumI += idx
    }

    Swag.assert(sumV == 16)
    Swag.assert(sumI == 3)
}

// A '&name' binding stays mutable when the iterated storage is mutable. The immutable
// counterpart is rejected at compile time, see 'sema_err_for_struct_binding_const'.

#test
{
    var values = [1, 2, 3]
    for &v in values do
        v[] = 9
    Swag.assert(values[0] == 9 and values[1] == 9 and values[2] == 9)
}

#test
{
    // 'let' freezes a slice handle, never the storage it designates.
    var backing        = [1, 2, 3]
    let view: [..] s32 = backing
    for &v in view do
        v[] = 7
    Swag.assert(backing[0] == 7 and backing[1] == 7 and backing[2] == 7)
}

#test
{
    // An immutable array still iterates by value.
    let values = [1, 2, 3]
    var sum    = 0
    for v in values do
        sum += v
    Swag.assert(sum == 6)
}
