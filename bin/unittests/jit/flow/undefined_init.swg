#global private

// Runtime behavior of '= undefined' locals under the definite-assignment analysis:
// the first initializing assignment is compiled as an initialization, so the
// garbage destination is never dropped; real reassignments still drop.

var g_UndDropCount: s32

struct UndDrop
{
    value: s32
}

impl UndDrop
{
    mtd opDrop()
    {
        g_UndDropCount += 1
    }
}

func mkUndDrop(v: s32)->UndDrop
{
    var result: retval
    result.value = v
    return result
}

struct UndOuter
{
    d: UndDrop
    x: s32
}

func undFillPtr(p: *s32)
{
    dref p = 42
}

func undPair()->{ x: s32, y: s32 }
{
    var result: retval = undefined
    result.x = 1
    result.y = 2
    return result
}

// Straight-line scalar init.
#test
{
    var x: s32 = undefined
    x = 7
    @assert(x == 7)
}

// Out parameter: taking the address counts as initialization.
#test
{
    var x: s32 = undefined
    undFillPtr(&x)
    @assert(x == 42)
}

// Array fill loop: writing elements initializes the aggregate, and the facts
// survive the loop.
#test
{
    var arr: [8] s32 = undefined
    for i in 8 do
        arr[i] = cast(s32) i
    var sum = 0's32
    for i in 8 do
        sum += arr[i]
    @assert(sum == 28)
}

// Destructuring assignment initializes every element.
#test
{
    var a: s32 = undefined
    var b: s32 = undefined
    (a, b) = undPair()
    @assert(a == 1 and b == 2)
}

// defer reading a variable initialized later.
#test
{
    var x: s32 = undefined
    defer @assert(x == 9)
    x = 9
}

// First assignment of a droppable destination is an initialization: the old
// (garbage) content must NOT be dropped. Exactly one drop: the scope exit.
#test
{
    g_UndDropCount = 0
    {
        var v: UndDrop = undefined
        v = mkUndDrop(5)
        @assert(v.value == 5)
    }
    @assert(g_UndDropCount == 1)
}

// Same at field granularity.
#test
{
    g_UndDropCount = 0
    {
        var o: UndOuter = undefined
        o.d = mkUndDrop(3)
        o.x = 4
        @assert(o.d.value == 3 and o.x == 4)
    }
    @assert(g_UndDropCount == 1)
}

// A real reassignment after full initialization still drops the previous value.
#test
{
    g_UndDropCount = 0
    {
        var v: UndDrop = undefined
        v = mkUndDrop(1)
        v = mkUndDrop(2)
        @assert(v.value == 2)
    }
    @assert(g_UndDropCount == 2)
}
