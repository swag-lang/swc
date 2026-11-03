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

    var result: #returntype
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
    scope
    {
        let value = catch makeManagedResult(true)
        Swag.require(value.value == 11)
    }
    Swag.require(PostCopyCount == 0)
    Swag.require(PostMoveCount == 0)
    Swag.require(DropCount == 1)
    Swag.require(DropTrace == 11)
}

// A failed call has no live result ownership, so synthesizing its zero fallback does not
// run a copy lifecycle.
#test
{
    resetHooks(13)
    scope
    {
        let value = catch makeManagedResult(false)
        Swag.require(value.value == 0)
    }
    Swag.require(PostCopyCount == 0)
    Swag.require(PostMoveCount == 0)
    Swag.require(DropCount == 1)
    Swag.require(DropTrace == 0)
}

#test
{
    resetHooks(17)
    scope
    {
        let value = expect makeManagedResult(true)
        Swag.require(value.value == 17)
    }
    Swag.require(PostCopyCount == 0)
    Swag.require(PostMoveCount == 0)
    Swag.require(DropCount == 1)
    Swag.require(DropTrace == 17)
}

// Error-management wrappers forward the caller's return storage through a non-inlined function.
#test
{
    resetHooks(19)
    scope
    {
        let value = returnCatchResult()
        Swag.require(value.value == 19)
    }
    Swag.require(PostCopyCount == 0)
    Swag.require(PostMoveCount == 0)
    Swag.require(DropCount == 1)
    Swag.require(DropTrace == 19)

    resetHooks(23)
    scope
    {
        let value = returnExpectResult()
        Swag.require(value.value == 23)
    }
    Swag.require(PostCopyCount == 0)
    Swag.require(PostMoveCount == 0)
    Swag.require(DropCount == 1)
    Swag.require(DropTrace == 23)

    resetHooks(29)
    scope
    {
        let value = catch returnTryResult()
        Swag.require(value.value == 29)
    }
    Swag.require(PostCopyCount == 0)
    Swag.require(PostMoveCount == 0)
    Swag.require(DropCount == 1)
    Swag.require(DropTrace == 29)
}

// An inline expansion used as an initializer writes into the binding too: its synthetic
// result local does not introduce a copy or a move.
#test
{
    resetHooks(31)
    scope
    {
        let value = returnInlineCatchResult()
        Swag.require(value.value == 31)
    }
    Swag.require(PostCopyCount == 0)
    Swag.require(PostMoveCount == 0)
    Swag.require(DropCount == 1)
    Swag.require(DropTrace == 31)
}
