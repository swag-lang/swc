#global fileprivate

var Trace: s64 = 0

func resetTrace()
{
    Trace = 0
}

func appendTrace(value: s64)
{
    Trace = Trace * 10 + value
}

// Defer in nested if-else chains (no function-level defer to avoid return-capture confusion)
func deferNestedIfElse(a: bool, b: bool)->s64
{
    resetTrace()

    if a
    {
        defer appendTrace(1)
        if b
        {
            defer appendTrace(2)
            appendTrace(3)
        }
        else
        {
            defer appendTrace(4)
            appendTrace(5)
        }
    }
    else
    {
        defer appendTrace(6)
        appendTrace(7)
    }

    appendTrace(8)
    return Trace
}

#test
{
    // a=true, b=true: body=3, inner-defer=2, outer-if-defer=1, body=8
    @assert(deferNestedIfElse(true, true) == 3218)
}

#test
{
    // a=true, b=false: body=5, inner-defer=4, outer-if-defer=1, body=8
    @assert(deferNestedIfElse(true, false) == 5418)
}

#test
{
    // a=false: body=7, else-defer=6, body=8
    @assert(deferNestedIfElse(false, false) == 768)
}

// Multiple defers in same scope (LIFO order)
func deferMultipleSameScope()->s64
{
    resetTrace()
    {
        defer appendTrace(1)
        defer appendTrace(2)
        defer appendTrace(3)
        appendTrace(4)
    }
    return Trace
}

#test
{
    // body=4, then defers in reverse: 3, 2, 1
    @assert(deferMultipleSameScope() == 4321)
}

// Defer with nested loops
func deferNestedLoops()->s64
{
    resetTrace()
    for i in 3
    {
        defer appendTrace(cast(s64) i + 1)
        for j in 2
        {
            defer appendTrace(cast(s64) j + 5)
            if j == 0 do
                break
        }
    }
    return Trace
}

#test
{
    // iteration i=0: j=0 break (j-defer=5), i-defer=1
    // iteration i=1: j=0 break (j-defer=5), i-defer=2
    // iteration i=2: j=0 break (j-defer=5), i-defer=3
    @assert(deferNestedLoops() == 515253)
}

// Defer with while and multiple breaks
func deferWhileMultiBreak(path: s32)->s64
{
    resetTrace()
    var i = 0
    while i < 10
    {
        i += 1
        defer appendTrace(cast(s64) i)
        if path == 1 and i == 1 do
            break
        if path == 2 and i == 3 do
            break
    }
    return Trace
}

#test
{
    @assert(deferWhileMultiBreak(1) == 1) // i becomes 1, break, defer=1
}

#test
{
    @assert(deferWhileMultiBreak(2) == 123) // i=1 defer=1, i=2 defer=2, i=3 break defer=3
}

// Defer with scope block
func deferScopeBlock()->s64
{
    resetTrace()
    {
        defer appendTrace(1)
        appendTrace(2)
    }
    {
        defer appendTrace(3)
        appendTrace(4)
    }
    appendTrace(5)
    return Trace
}

#test
{
    // block1: body=2, defer=1; block2: body=4, defer=3; body=5
    @assert(deferScopeBlock() == 21435)
}

// Defer in single iteration for loop
func deferSingleIterFor()->s64
{
    resetTrace()
    for 1
    {
        defer appendTrace(1)
        appendTrace(2)
    }
    appendTrace(3)
    return Trace
}

#test
{
    @assert(deferSingleIterFor() == 213)
}

// Defer with block override (defer runs after block, overriding previous assignment)
#test
{
    var a = 0
    {
        defer a = 2
        a = 3
    }
    @assert(a == 2)
}

// Defer with multiple scope levels
func deferTripleNested()->s64
{
    resetTrace()
    {
        defer appendTrace(1)
        {
            defer appendTrace(2)
            {
                defer appendTrace(3)
                appendTrace(4)
            }
        }
    }
    return Trace
}

#test
{
    // innermost: body=4, defer=3; middle: defer=2; outer: defer=1
    @assert(deferTripleNested() == 4321)
}

// Defer in for with continue (defer still runs on continue)
func deferForContinue()->s64
{
    resetTrace()
    for i in 4
    {
        defer appendTrace(cast(s64) i + 1)
        if i % 2 == 0 do
            continue
        appendTrace(9)
    }
    return Trace
}

#test
{
    // i=0: continue, defer=1; i=1: body=9, defer=2; i=2: continue, defer=3; i=3: body=9, defer=4
    @assert(deferForContinue() == 192394)
}

// Defer ordering with early loop break
func deferForEarlyBreak()->s64
{
    resetTrace()
    for i in 100
    {
        defer appendTrace(cast(s64) i + 1)
        appendTrace(8)
        if i == 1 do
            break
    }
    return Trace
}

#test
{
    // i=0: body=8, defer=1; i=1: body=8, defer=2 (then break)
    @assert(deferForEarlyBreak() == 8182)
}
