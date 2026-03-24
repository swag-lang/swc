#global fileprivate

var GNativeDeferScalarObserved: s32
var GNativeDeferTextObserved:   string
var GNativeDeferArrayObserved:  s32
var GNativeDeferReturnObserved: s32

struct NativeDeferPoint
{
    value: s32
}

func nativeDeferMakePoint(value: s32)->NativeDeferPoint
{
    var result: NativeDeferPoint
    result.value = value
    return result
}

func nativeDeferIfVarDecl()->s32
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

func nativeDeferWithExprAndVar()->s32
{
    var state = 0
    var point: NativeDeferPoint

    with point = nativeDeferMakePoint(1) defer state = state * 10 + .value
    point.value = 2
    with let ptr = &point defer state = state * 10 + .value
    with var local = nativeDeferMakePoint(3) defer state = state * 10 + .value

    return state
}

func nativeDeferWhileBreakContinue()->s32
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

func nativeDeferForSingleStmtWhere()->s32
{
    var state = 0
    for i in 6 where (i & 1) == 0 do
        defer state = state * 10 + cast(s32) i + 2

    return state
}

func nativeDeferForBreakContinue()->s32
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

func nativeDeferForCStyleSingleStmt()->s32
{
    var state = 0
    for var i = 0; i < 3; i += 1 do
        defer state = state * 10 + i + 1

    return state
}

func nativeDeferForCStyleBreakContinue()->s32
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

func nativeDeferForeachSingleStmtWhere()->s32
{
    var state = 0
    var values: [4] s32 = [1, 2, 3, 4]
    foreach v in values where (v & 1) == 0 do
        defer state = state * 10 + v

    return state
}

func nativeDeferForeachBreakContinue()->s32
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

func nativeDeferInfiniteLoop()->s32
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

func nativeDeferSwitchBreak()->s32
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

func nativeDeferReturnScalar()->s32
{
    var value = 7
    defer
    {
        value = 9
        GNativeDeferScalarObserved = value
    }

    return value
}

func nativeDeferReturnString()->string
{
    var value = "A"
    defer
    {
        value = "B"
        GNativeDeferTextObserved = value
    }

    return value
}

func nativeDeferReturnArray()->[4] s32
{
    var values: [4] s32 = [1, 2, 3, 4]
    defer
    {
        values[0] = 9
        GNativeDeferArrayObserved = values[0]
    }

    return values
}

func nativeDeferReturnNestedScopes()->s32
{
    GNativeDeferReturnObserved = 0
    {
        defer GNativeDeferReturnObserved = GNativeDeferReturnObserved * 10 + 1
        {
            defer GNativeDeferReturnObserved = GNativeDeferReturnObserved * 10 + 2
            return 7
        }
    }
}

#test
{
    var state = 0
    {
        defer state = state * 10 + 1
        defer state = state * 10 + 2
        defer state = state * 10 + 3
    }
    @assert(state == 321)
}

#test
{
    var state = 0
    {
        defer state = state * 10 + 1
        {
            defer state = state * 10 + 2
        }

        @assert(state == 2)
    }

    @assert(state == 21)
}

#test
{
    var state = 0
    {
        defer
        {
            defer state = state * 10 + 1
            state = state * 10 + 2
        }
    }

    @assert(state == 21)
}

#test
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
    @assert(state == 123)
}

#test
{
    @assert(nativeDeferIfVarDecl() == 345)
}

#test
{
    @assert(nativeDeferWithExprAndVar() == 123)
}

#test
{
    var i = 0
    var state = 0
    while i < 3 do
        defer
        {
            i += 1
            state = state * 10 + i
        }

    @assert(state == 123)
}

#test
{
    @assert(nativeDeferWhileBreakContinue() == 1234)
}

#test
{
    @assert(nativeDeferForSingleStmtWhere() == 246)
    @assert(nativeDeferForBreakContinue() == 1234)
    @assert(nativeDeferForCStyleSingleStmt() == 123)
    @assert(nativeDeferForCStyleBreakContinue() == 1234)
}

#test
{
    @assert(nativeDeferForeachSingleStmtWhere() == 24)
    @assert(nativeDeferForeachBreakContinue() == 1234)
    @assert(nativeDeferInfiniteLoop() == 123)
}

#test
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

    @assert(state == 12)
    @assert(nativeDeferSwitchBreak() == 1)
}

#test
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

    @assert(state == 21)
}

#test
{
    GNativeDeferScalarObserved = 0
    @assert(nativeDeferReturnScalar() == 7)
    @assert(GNativeDeferScalarObserved == 9)

    GNativeDeferTextObserved = ""
    @assert(nativeDeferReturnString() == "A")
    @assert(GNativeDeferTextObserved == "B")

    GNativeDeferArrayObserved = 0
    let values = nativeDeferReturnArray()
    @assert(values[0] == 1)
    @assert(values[1] == 2)
    @assert(values[2] == 3)
    @assert(values[3] == 4)
    @assert(GNativeDeferArrayObserved == 9)

    GNativeDeferReturnObserved = 0
    @assert(nativeDeferReturnNestedScopes() == 7)
    @assert(GNativeDeferReturnObserved == 21)
}
