#global fileprivate

struct JitWithVarPoint
{
    x: s32
    y: s32
}

func jitWithVarMakePoint(x, y: s32)->JitWithVarPoint
{
    var result: JitWithVarPoint
    result.x = x
    result.y = y
    return result
}

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

func jitWithLocalInit()->s32
{
    with var pair = jitWithRetval()
    {
        .a += 1
        .b += 2
    }

    return pair.a * 100 + pair.b
}

func jitWithRetvalUndefined()->{ a, b: s32 }
{
    with var result: retval = undefined
    {
        .a = 55
        .b = 89
    }

    return result
}

func jitWithLetPointer()->s32
{
    var point = jitWithVarMakePoint(10, 20)
    with let ptr = &point
    {
        .x += 3
        .y += 4
    }

    return ptr.x * 100 + ptr.y
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

#test
{
    const value = #run jitWithLocalInit()
    @assert(value == 2236)
}

#test
{
    const pair = #run jitWithRetvalUndefined()
    @assert(pair.a == 55)
    @assert(pair.b == 89)
}

#test
{
    const value = #run jitWithLetPointer()
    @assert(value == 1324)
}
