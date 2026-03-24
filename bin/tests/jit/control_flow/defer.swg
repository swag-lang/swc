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

struct DeferReturnInfo
{
    value: s32
    trace: s64
}

#test
{
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

    const V = #run deferScopeOrder()
    #assert(V == 42315)
}

#test
{
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

    const V = #run deferFunctionReturnTrace()
    #assert(V.value == 42)
    #assert(V.trace == 19)
}

#test
{
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

    const V0 = #run deferIfBranch(true)
    const V1 = #run deferIfBranch(false)
    #assert(V0 == 215)
    #assert(V1 == 435)
}

#test
{
    func deferIfSingleStmtExecutesImmediately(takeIf: bool)->s64
    {
        resetDeferTrace()
        if takeIf do
            defer appendDeferTrace(1)

        appendDeferTrace(2)
        return DeferTrace
    }

    const V0 = #run deferIfSingleStmtExecutesImmediately(true)
    const V1 = #run deferIfSingleStmtExecutesImmediately(false)
    #assert(V0 == 12)
    #assert(V1 == 2)
}

#test
{
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

    const V = #run deferWhileControl()
    #assert(V == 9123)
}

#test
{
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

    const V = #run deferWhileReturnTrace()
    #assert(V.value == 42)
    #assert(V.trace == 172)
}

#test
{
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

    const V = #run deferForCStyle()
    #assert(V == 8123)
}

#test
{
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

    const V = #run deferForRange()
    #assert(V == 6123)
}

#test
{
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

    const V = #run deferForeach()
    #assert(V == 7123)
}

#test
{
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
                appendDeferTrace(5)
        }

        return DeferTrace
    }

    const V0 = #run deferSwitch(1)
    const V1 = #run deferSwitch(2)
    const V2 = #run deferSwitch(3)
    const V3 = #run deferSwitch(9)
    #assert(V0 == 8192)
    #assert(V1 == 92)
    #assert(V2 == 43)
    #assert(V3 == 5)
}

#test
{
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

    const V = #run deferBreakToScope()
    #assert(V == 213)
}
