#global fileprivate

var DeferTrace: s64 = 0

func resetDeferTrace()
{
    DeferTrace = 0
}

func appendDeferTrace(value: s64)
{
    DeferTrace = DeferTrace * 10 + value
}

func deferValue()->s64
{
    return 6
}

struct DeferReturnInfo
{
    value: s32
    trace: s64
}

struct DeferDropTracker {}

var DropCount: u32 = 0

impl DeferDropTracker
{
    func opDrop(me)
    {
        DropCount += 1
    }
}

struct DeferDropInfo
{
    count: s32
    drops: u32
}

struct ErrDefer {}

#[Swag.Inline]
func deferThrowLeaf() throw
{
    defer appendDeferTrace(1)
    throw ErrDefer{}
}

#[Swag.Inline]
func deferThrowMid() throw
{
    defer appendDeferTrace(2)
    try deferThrowLeaf()
}

#[Swag.Inline]
func deferThrowTop() throw
{
    defer appendDeferTrace(4)
    try deferThrowMid()
}

func deferScopeOrder()->s64
{
    resetDeferTrace()
    {
        defer appendDeferTrace(1)
        defer
        {
            appendDeferTrace(2)
            appendDeferTrace(3)
        }

        appendDeferTrace(4)
    }

    appendDeferTrace(5)
    return DeferTrace
}

func deferFunctionReturnTrace()->DeferReturnInfo
{
    resetDeferTrace()
    with var result: retval
    {
        .value = 42
        .trace = -1
    }

    defer result.trace = DeferTrace
    defer appendDeferTrace(9)
    appendDeferTrace(1)
    return result
}

func deferIfBranch(takeIf: bool)->s64
{
    resetDeferTrace()
    if takeIf
    {
        defer appendDeferTrace(1)
        appendDeferTrace(2)
    }
    else
    {
        defer appendDeferTrace(3)
        appendDeferTrace(4)
    }

    appendDeferTrace(5)
    return DeferTrace
}

func deferIfSingleStmtExecutesImmediately(takeIf: bool)->s64
{
    resetDeferTrace()
    if takeIf do
        defer appendDeferTrace(1)

    appendDeferTrace(2)
    return DeferTrace
}

func deferWhileControl()->s64
{
    resetDeferTrace()
    var i: s32 = 0

    while i < 4
    {
        i += 1
        defer appendDeferTrace(cast(s64) i)

        if i == 2 do
            continue
        if i == 3 do
            break

        appendDeferTrace(9)
    }

    return DeferTrace
}

func deferWhileReturnTrace()->DeferReturnInfo
{
    resetDeferTrace()
    with var result: retval
    {
        .value = -1
        .trace = -1
    }

    defer result.trace = DeferTrace
    var i: s32 = 0

    while i < 4
    {
        i += 1
        defer appendDeferTrace(cast(s64) i)

        if i == 2
        {
            result.value = 42
            appendDeferTrace(7)
            return result
        }
    }

    return result
}

func deferBlockBodyTrace()->DeferReturnInfo
{
    with var result: retval
    {
        .value = 666
        .trace = 0
    }

    defer
    {
        result.trace = deferValue()
    }

    return result
}

func deferNestedLoopControl()->s32
{
    var count = 0
    for 10
    {
        defer count -= 1
        {
            defer count += 2
            continue
        }
    }

    return count
}

func deferForCStyle()->s64
{
    resetDeferTrace()
    for var i = 0; i < 4; i += 1
    {
        defer appendDeferTrace(cast(s64) i + 1)

        if i == 1 do
            continue
        if i == 2 do
            break

        appendDeferTrace(8)
    }

    return DeferTrace
}

func deferForRange()->s64
{
    resetDeferTrace()
    for i in 1 to 4
    {
        defer appendDeferTrace(cast(s64) i)

        if i == 2 do
            continue
        if i == 3 do
            break

        appendDeferTrace(6)
    }

    return DeferTrace
}

func deferForeach()->s64
{
    resetDeferTrace()
    var arr: [4] s32 = [1, 2, 3, 4]

    foreach v in arr
    {
        defer appendDeferTrace(cast(s64) v)

        if v == 2 do
            continue
        if v == 3 do
            break

        appendDeferTrace(7)
    }

    return DeferTrace
}

func deferSwitch(v: s32)->s64
{
    resetDeferTrace()
    switch v
    {
        case 1:
            defer appendDeferTrace(1)
            appendDeferTrace(8)
            fallthrough

        case 2:
            defer appendDeferTrace(2)
            appendDeferTrace(9)
            break

        case 3:
            defer appendDeferTrace(3)
            appendDeferTrace(4)
            break

        default:
            defer appendDeferTrace(5)
            appendDeferTrace(6)
    }

    return DeferTrace
}

func deferBreakToScopeAndDrop()->DeferDropInfo
{
    DropCount = 0
    with var result: retval
    {
        .count = 0
        .drops = 0
    }

    #scope(Outer)
    {
        var x: DeferDropTracker
        defer result.count += 1
        for 1
        {
            var y: DeferDropTracker
            defer result.count += 1
            break to Outer
        }
    }

    result.drops = DropCount
    return result
}

func deferEarlyReturnBeforeRegistration()->s64
{
    resetDeferTrace()
    appendDeferTrace(1)
    return DeferTrace
    defer appendDeferTrace(2)
}

func deferThrowTrace()->s64
{
    resetDeferTrace()
    catch deferThrowTop()
    return DeferTrace
}

func deferBreakToScope()->s64
{
    resetDeferTrace()
    #scope(Outer)
    {
        defer appendDeferTrace(1)
        {
            defer appendDeferTrace(2)
            break to Outer
        }

        appendDeferTrace(9)
    }

    appendDeferTrace(3)
    return DeferTrace
}

#test
{
    @assert(deferScopeOrder() == 42315)
}

#test
{
    let v = deferFunctionReturnTrace()
    @assert(v.value == 42)
    @assert(v.trace == 19)
}

#test
{
    @assert(deferIfBranch(true) == 215)
    @assert(deferIfBranch(false) == 435)
}

#test
{
    @assert(deferIfSingleStmtExecutesImmediately(true) == 12)
    @assert(deferIfSingleStmtExecutesImmediately(false) == 2)
}

#test
{
    @assert(deferWhileControl() == 9123)
}

#test
{
    let v = deferWhileReturnTrace()
    @assert(v.value == 42)
    @assert(v.trace == 172)
}

#test
{
    let v = deferBlockBodyTrace()
    @assert(v.value == 666)
    @assert(v.trace == 6)
}

#test
{
    @assert(deferNestedLoopControl() == 10)
}

#test
{
    @assert(deferForCStyle() == 8123)
}

#test
{
    @assert(deferForRange() == 6123)
}

#test
{
    @assert(deferForeach() == 7123)
}

#test
{
    @assert(deferSwitch(1) == 8192)
    @assert(deferSwitch(2) == 92)
    @assert(deferSwitch(3) == 43)
    @assert(deferSwitch(9) == 65)
}

/*
#test
{
    let v = deferBreakToScopeAndDrop()
    @assert(v.count == 2)
    @assert(v.drops == 2)
}

#test
{
    @assert(deferEarlyReturnBeforeRegistration() == 1)
}

#test
{
    @assert(deferThrowTrace() == 124)
}
*/

#test
{
    @assert(deferBreakToScope() == 213)
}

#test
{
    var a = 0
    {
        defer a = 2
        a = 3
    }
    @assert(a == 2)
}

/*
#[Swag.Mixin]
func scopeLock()
{
    var a = 4
    defer G = a
}

var G = 0

//#[Swag.PrintBc]
#test
{
    {
        scopeLock()
        @assert(a == 4)
        defer a += 1
    }

    @print(G)
    @assert(G == 5)
}
*/