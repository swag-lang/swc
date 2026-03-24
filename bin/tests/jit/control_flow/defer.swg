#global fileprivate

var GJitDeferScalarObserved: s32
var GJitDeferTextObserved:   string
var GJitDeferArrayObserved:  s32
var GJitDeferReturnObserved: s32

struct JitDeferPoint
{
    value: s32
}

func jitDeferMakePoint(value: s32)->JitDeferPoint
{
    var result: JitDeferPoint
    result.value = value
    return result
}

func jitDeferReverse()->s32
{
    var state = 0
    {
        defer state = state * 10 + 1
        defer state = state * 10 + 2
        defer state = state * 10 + 3
    }
    return state
}

func jitDeferNestedScopes()->s32
{
    var state = 0
    {
        defer state = state * 10 + 1
        {
            defer state = state * 10 + 2
        }
    }

    return state
}

func jitDeferNestedDeferredBlock()->s32
{
    var state = 0
    {
        defer
        {
            defer state = state * 10 + 1
            state = state * 10 + 2
        }
    }

    return state
}

func jitDeferIfBranches()->s32
{
    var state = 0
    if true do
        defer state = state * 10 + 1
    if false do
        defer state = state * 10 + 9
    elif true do
        defer state = state * 10 + 2
    else do
        defer state = state * 10 + 8
    if false do
        defer state = state * 10 + 9
    else do
        defer state = state * 10 + 3
    return state
}

func jitDeferIfVarDecl()->s32
{
    var state = 0
    if var x = 3 do
        defer state = state * 10 + x
    if var y = 0 where y == 0 do
        defer state = state * 10 + y + 4
    if var z = 1 where false do
        defer state = state * 10 + 9
    else do
        defer state = state * 10 + z + 4
    return state
}

func jitDeferWithExprAndVar()->s32
{
    var state = 0
    var point: JitDeferPoint

    with point = jitDeferMakePoint(1) defer state = state * 10 + .value
    point.value = 2
    with let ptr = &point defer state = state * 10 + .value
    with var local = jitDeferMakePoint(3) defer state = state * 10 + .value

    return state
}

func jitDeferWhileSingleStmt()->s32
{
    var i = 0
    var state = 0
    while i < 3 do
        defer
        {
            i += 1
            state = state * 10 + i
        }

    return state
}

func jitDeferWhileBreakContinue()->s32
{
    var i = 0
    var state = 0
    while true
    {
        i += 1
        defer state = state * 10 + i
        if i < 4 do
            continue
        break
    }

    return state
}

func jitDeferForSingleStmtWhere()->s32
{
    var state = 0
    for i in 6 where (i & 1) == 0 do
        defer state = state * 10 + cast(s32) i + 2

    return state
}

func jitDeferForBreakContinue()->s32
{
    var state = 0
    for i in 4
    {
        defer state = state * 10 + cast(s32) i + 1
        if i < 3 do
            continue
        break
    }

    return state
}

func jitDeferForCStyleSingleStmt()->s32
{
    var state = 0
    for var i = 0; i < 3; i += 1 do
        defer state = state * 10 + i + 1

    return state
}

func jitDeferForCStyleBreakContinue()->s32
{
    var state = 0
    for var i = 0; i < 4; i += 1
    {
        defer state = state * 10 + i + 1
        if i < 3 do
            continue
        break
    }

    return state
}

func jitDeferForeachSingleStmtWhere()->s32
{
    var state = 0
    var values: [4] s32 = [1, 2, 3, 4]
    foreach v in values where (v & 1) == 0 do
        defer state = state * 10 + v

    return state
}

func jitDeferForeachBreakContinue()->s32
{
    var state = 0
    var values: [4] s32 = [1, 2, 3, 4]
    foreach v in values
    {
        defer state = state * 10 + v
        if v < 4 do
            continue
        break
    }

    return state
}

func jitDeferInfiniteLoop()->s32
{
    var i = 0
    var state = 0
    for
    {
        i += 1
        defer state = state * 10 + i
        if i < 3 do
            continue
        break
    }

    return state
}

func jitDeferSwitchBreak()->s32
{
    var state = 0
    switch 0
    {
    case 0:
        defer state = state * 10 + 1
        break
    default:
        defer state = state * 10 + 9
        break
    }

    return state
}

func jitDeferSwitchFallthrough()->s32
{
    var state = 0
    switch 0
    {
    case 0:
        defer state = state * 10 + 1
        fallthrough
    case 1:
        defer state = state * 10 + 2
    }

    return state
}

func jitDeferScopedBreak()->s32
{
    var state = 0
    #scope(Outer)
    {
        defer state = state * 10 + 1
        #scope(Inner)
        {
            defer state = state * 10 + 2
            break to Outer
        }
    }

    return state
}

func jitDeferReturnScalar()->s32
{
    var value = 7
    defer
    {
        value = 9
        GJitDeferScalarObserved = value
    }

    return value
}

func jitDeferReturnString()->string
{
    var value = "A"
    defer
    {
        value = "B"
        GJitDeferTextObserved = value
    }

    return value
}

func jitDeferReturnArray()->[4] s32
{
    var values: [4] s32 = [1, 2, 3, 4]
    defer
    {
        values[0] = 9
        GJitDeferArrayObserved = values[0]
    }

    return values
}

func jitDeferReturnNestedScopes()->s32
{
    GJitDeferReturnObserved = 0
    {
        defer GJitDeferReturnObserved = GJitDeferReturnObserved * 10 + 1
        {
            defer GJitDeferReturnObserved = GJitDeferReturnObserved * 10 + 2
            return 7
        }
    }
}

func jitDeferReturnScalarObserved()->s32
{
    GJitDeferScalarObserved = 0
    discard jitDeferReturnScalar()
    return GJitDeferScalarObserved
}

func jitDeferReturnStringObserved()->string
{
    GJitDeferTextObserved = ""
    discard jitDeferReturnString()
    return GJitDeferTextObserved
}

func jitDeferReturnArrayObserved()->s32
{
    GJitDeferArrayObserved = 0
    discard jitDeferReturnArray()
    return GJitDeferArrayObserved
}

func jitDeferReturnNestedScopesObserved()->s32
{
    GJitDeferReturnObserved = 0
    discard jitDeferReturnNestedScopes()
    return GJitDeferReturnObserved
}

#test
{
    #assert(#run jitDeferReverse() == 321)
    #assert(#run jitDeferNestedScopes() == 21)
    #assert(#run jitDeferNestedDeferredBlock() == 21)
    #assert(#run jitDeferIfBranches() == 123)
    #assert(#run jitDeferIfVarDecl() == 345)
    #assert(#run jitDeferWithExprAndVar() == 123)
    #assert(#run jitDeferWhileSingleStmt() == 123)
    #assert(#run jitDeferWhileBreakContinue() == 1234)
    #assert(#run jitDeferForSingleStmtWhere() == 246)
    #assert(#run jitDeferForBreakContinue() == 1234)
    #assert(#run jitDeferForCStyleSingleStmt() == 123)
    #assert(#run jitDeferForCStyleBreakContinue() == 1234)
    #assert(#run jitDeferForeachSingleStmtWhere() == 24)
    #assert(#run jitDeferForeachBreakContinue() == 1234)
    #assert(#run jitDeferInfiniteLoop() == 123)
    #assert(#run jitDeferSwitchBreak() == 1)
    #assert(#run jitDeferSwitchFallthrough() == 12)
    #assert(#run jitDeferScopedBreak() == 21)

    #assert(#run jitDeferReturnScalar() == 7)
    #assert(#run jitDeferReturnScalarObserved() == 9)

    #assert(#run jitDeferReturnString() == "A")
    #assert(#run jitDeferReturnStringObserved() == "B")

    const values = #run jitDeferReturnArray()
    #assert(values[0] == 1)
    #assert(values[1] == 2)
    #assert(values[2] == 3)
    #assert(values[3] == 4)
    #assert(#run jitDeferReturnArrayObserved() == 9)

    #assert(#run jitDeferReturnNestedScopes() == 7)
    #assert(#run jitDeferReturnNestedScopesObserved() == 21)
}
