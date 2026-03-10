#global fileprivate

#[Swag.Inline]
func inlineTypedVariadicSum(base: s32, values: s32...)->s32
{
    var sum0: s32 = base
    foreach v in values
    {
        sum0 += v
    }
    return sum0 + cast(s32) @countof(values)
}

#[Swag.Inline]
func inlineTypedVariadicNamed(values: s32...)->s32
{
    var sum1: s32 = 0
    foreach v in values
    {
        sum1 += v
    }
    return sum1
}

#[Swag.Inline]
func inlineUntypedVariadicScore(values: ...)->s32
{
    var sum2: s32 = 0
    foreach v in values
    {
        switch @kindof(v)
        {
        case s32:
            sum2 += cast(s32) v
        case bool:
            if cast(bool) v
            {
                sum2 += 10
            }
        case string:
            sum2 += (cast(string) v)[0]
        }
    }

    return sum2
}

#[Swag.Inline]
func inlineUntypedVariadicHead(head: s32, values: ...)->s32
{
    return head + cast(s32) @countof(values)
}

#test
{
    var t0: s32 = 1
    var t1: s32 = 2
    var t2: s32 = 3
    var t3: s32 = 4
    @assert(inlineTypedVariadicSum(t0, t1, t2, t3) == 13)

    var t4: s32 = 5
    @assert(inlineTypedVariadicSum(t4) == 5)

    var n0: s32 = 7
    var n1: s32 = 8
    var n2: s32 = 9
    @assert(inlineTypedVariadicNamed(n0, n1, n2) == 24)

    var u0: s32 = 1
    var u1: bool = true
    var u2: string = "A"
    @assert(inlineUntypedVariadicScore(u0, u1, u2) == 76)

    var u3: s32 = 2
    var u4: bool = false
    var u5: string = "B"
    var u6: s32 = 3
    @assert(inlineUntypedVariadicScore(u3, u4, u5, u6) == 71)

    var h0: s32 = 40
    var h1: s32 = 1
    var h2: string = "a"
    var h3: bool = false
    @assert(inlineUntypedVariadicHead(h0, h1, h2, h3) == 43)

    var h4: s32 = 50
    var h5: string = "x"
    @assert(inlineUntypedVariadicHead(h4, h5) == 51)
}
