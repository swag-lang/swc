#global fileprivate

func jitWithAnonymous()->s32
{
    with var pair: { a, b: s32 }
    {
        .a = 8
        .b = 13
    }

    return pair.a * 100 + pair.b
}

func jitWithRetval()->{ a, b: s32 }
{
    with var result: retval
    {
        .a = 21
        .b = 34
    }

    return result
}

#test
{
    const value = #run jitWithAnonymous()
    @assert(value == 813)
}

#test
{
    const pair = #run jitWithRetval()
    @assert(pair.a == 21)
    @assert(pair.b == 34)
}
