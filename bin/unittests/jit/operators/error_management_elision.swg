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
        DropTrace = DropTrace * 100 + cast(s64) .value
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
    if !succeed do
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
