#global private

var DropCount:     u32 = 0
var DropTrace:     s64 = 0
var PostCopyCount: u32 = 0
var PostMoveCount: u32 = 0
var g_seed:        s32 = 0

func resetHooks(seed: s32)
{
    DropCount     = 0
    DropTrace     = 0
    PostCopyCount = 0
    PostMoveCount = 0
    g_seed        = seed
}

struct ManagedResult
{
    value: s32
    pad:   [3] s64
}

impl ManagedResult
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64, .value)
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
    }
}

#[Swag.NoInline]
func makeManagedResult(succeed: bool)->ManagedResult fail
{
    if not succeed do
        fail Swag.BaseError{"expected failure"}

    var result: retval
    result.value = g_seed
    return result
}

func returnCatchResult()->ManagedResult
{
    return catch makeManagedResult(true)
}

func returnExpectResult()->ManagedResult
{
    return expect makeManagedResult(true)
}

func returnTryResult()->ManagedResult fail
{
    return try makeManagedResult(true)
}

#[Swag.Inline]
func returnInlineCatchResult()->ManagedResult
{
    return catch makeManagedResult(true)
}

// A handled call constructs its successful result directly in the binding.
#test
{
    resetHooks(11)
    {
        let value = catch makeManagedResult(true)
        Swag.assert(value.value == 11)
    }
    Swag.assert(PostCopyCount == 0)
    Swag.assert(PostMoveCount == 0)
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 11)
}

// A failed call has no live result ownership, so synthesizing its zero fallback does not
// run a copy lifecycle.
#test
{
    resetHooks(13)
    {
        let value = catch makeManagedResult(false)
        Swag.assert(value.value == 0)
    }
    Swag.assert(PostCopyCount == 0)
    Swag.assert(PostMoveCount == 0)
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 0)
}

#test
{
    resetHooks(17)
    {
        let value = expect makeManagedResult(true)
        Swag.assert(value.value == 17)
    }
    Swag.assert(PostCopyCount == 0)
    Swag.assert(PostMoveCount == 0)
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 17)
}

// Error-management wrappers forward the caller's return storage through a non-inlined function.
#test
{
    resetHooks(19)
    {
        let value = returnCatchResult()
        Swag.assert(value.value == 19)
    }
    Swag.assert(PostCopyCount == 0)
    Swag.assert(PostMoveCount == 0)
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 19)

    resetHooks(23)
    {
        let value = returnExpectResult()
        Swag.assert(value.value == 23)
    }
    Swag.assert(PostCopyCount == 0)
    Swag.assert(PostMoveCount == 0)
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 23)

    resetHooks(29)
    {
        let value = catch returnTryResult()
        Swag.assert(value.value == 29)
    }
    Swag.assert(PostCopyCount == 0)
    Swag.assert(PostMoveCount == 0)
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 29)
}

// An inline expansion used as an initializer writes into the binding too: its synthetic
// result local does not introduce a copy or a move.
#test
{
    resetHooks(31)
    {
        let value = returnInlineCatchResult()
        Swag.assert(value.value == 31)
    }
    Swag.assert(PostCopyCount == 0)
    Swag.assert(PostMoveCount == 0)
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 31)
}

// Returns a named local rather than the 'retval' slot: the return moves it out.
#[Swag.NoInline]
func makeManagedLocal(succeed: bool)->ManagedResult fail
{
    if not succeed do
        fail Swag.BaseError{"expected failure"}

    var result: ManagedResult
    result.value = g_seed
    return result
}

#[Swag.NoInline]
func bindTryResult(succeed: bool)->s32 fail
{
    let value = try makeManagedResult(succeed)
    return value.value
}

#[Swag.NoInline]
func bindTypedTryResult(succeed: bool)->s32 fail
{
    var value: ManagedResult = try makeManagedResult(succeed)
    return value.value
}

#[Swag.NoInline]
func assignTryResult(succeed: bool)->s32 fail
{
    var value: ManagedResult
    value = try makeManagedResult(succeed)
    return value.value
}

func expectHooks(copies, moves, drops: u32, trace: s64)
{
    Swag.assert(PostCopyCount == copies)
    Swag.assert(PostMoveCount == moves)
    Swag.assert(DropCount == drops)
    Swag.assert(DropTrace == trace)
}

// 'try' constructs its result in the binding like 'catch' and 'expect' do, whether the
// binding infers its type or states it. A failure leaves before the binding exists.
#test
{
    resetHooks(37)
    let inferred = catch bindTryResult(true)
    Swag.assert(inferred == 37)
    expectHooks(0, 0, 1, 37)

    resetHooks(41)
    let typed = catch bindTypedTryResult(true)
    Swag.assert(typed == 41)
    expectHooks(0, 0, 1, 41)

    resetHooks(43)
    let failed = catch bindTryResult(false)
    Swag.assert(failed == 0)
    expectHooks(0, 0, 0, 0)

    resetHooks(47)
    let failedTyped = catch bindTypedTryResult(false)
    Swag.assert(failedTyped == 0)
    expectHooks(0, 0, 0, 0)
}

// A stated type and a mutable binding take the handled result the same way.
#test
{
    resetHooks(53)
    {
        let value: ManagedResult = catch makeManagedResult(true)
        Swag.assert(value.value == 53)
    }
    expectHooks(0, 0, 1, 53)

    resetHooks(59)
    {
        var value = expect makeManagedResult(true)
        Swag.assert(value.value == 59)
    }
    expectHooks(0, 0, 1, 59)
}

// A callee that returns a named local moves it into the binding: the only hook is that move.
#test
{
    resetHooks(61)
    {
        let value = catch makeManagedLocal(true)
        Swag.assert(value.value == 61)
    }
    expectHooks(0, 1, 1, 61)

    resetHooks(67)
    {
        let value = catch makeManagedLocal(false)
        Swag.assert(value.value == 0)
    }
    expectHooks(0, 0, 1, 0)
}

// Assigning a handled result adopts the call's temporary: the replaced value is dropped,
// the temporary moves in, and nothing is copied or left behind.
#test
{
    resetHooks(71)
    {
        var value: ManagedResult
        value = catch makeManagedResult(true)
        Swag.assert(value.value == 71)
    }
    expectHooks(0, 1, 2, 71)

    resetHooks(73)
    {
        var value: ManagedResult
        value = expect makeManagedResult(true)
        Swag.assert(value.value == 73)
    }
    expectHooks(0, 1, 2, 73)

    resetHooks(79)
    let propagated = catch assignTryResult(true)
    Swag.assert(propagated == 79)
    expectHooks(0, 1, 2, 79)
}

// A failed call assigns its zero fallback under 'catch', and under 'try' leaves with the
// target untouched.
#test
{
    resetHooks(83)
    {
        var value: ManagedResult
        value = catch makeManagedResult(false)
        Swag.assert(value.value == 0)
    }
    expectHooks(0, 1, 2, 0)

    resetHooks(89)
    let propagated = catch assignTryResult(false)
    Swag.assert(propagated == 0)
    expectHooks(0, 0, 1, 0)
}

// The result of an inline expansion is an owned temporary too.
#test
{
    resetHooks(97)
    {
        var value: ManagedResult
        value = returnInlineCatchResult()
        Swag.assert(value.value == 97)
    }
    expectHooks(0, 1, 2, 97)
}
