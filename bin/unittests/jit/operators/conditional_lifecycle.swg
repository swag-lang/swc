#global private

// A conditional expression selecting a struct forwards the winning operand's storage,
// so binding its result is a deep copy: 'opPostCopy' runs on the new binding and the
// selected operand keeps its own resources. Before the fix the binding was a raw bit
// copy — it aliased the winning variable's resources, and its scope-exit drop released
// them under the still-live source.
//
// 'opPostCopy' adds 10 to the value so the assertions can tell which storage the hook
// ran on: the binding must observe the increment, the source must not.
//
// The selected temporary arm is copied too; the abandoned temporary is not dropped
// today (temporaries have no drop scope yet), which keeps the drop counts below.

var DropCount:     u32 = 0
var DropTrace:     s64 = 0
var PostCopyCount: u32 = 0
var PostMoveCount: u32 = 0
var g_pick             = false

func resetHooks()
{
    DropCount     = 0
    DropTrace     = 0
    PostCopyCount = 0
    PostMoveCount = 0
}

struct Tracked
{
    value: s32 = 5
    a:     s64
    b:     s64
}

impl Tracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64) .value
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
        .value        += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
    }
}

#[Swag.NoInline]
func makeTracked(v: s32)->Tracked
{
    var result: Tracked
    result.value = v
    return result
}

// Selecting the lvalue arm copies it: the binding sees the post-copy, the source does
// not, and each owner drops its own value exactly once.
#test
{
    resetHooks()
    g_pick = false
    {
        var source = makeTracked(1)
        {
            let picked = g_pick ? makeTracked(2) : source
            @assert(picked.value == 11)
            @assert(source.value == 1)
            @assert(PostCopyCount == 1)
        }
        @assert(source.value == 1)
        @assert(DropCount == 1)
    }
    @assert(DropCount == 2)
    @assert(DropTrace == 1101)
}

// Selecting the temporary arm copies it the same way; the untouched lvalue arm keeps
// its resources.
#test
{
    resetHooks()
    g_pick = true
    {
        var source = makeTracked(1)
        {
            let picked = g_pick ? makeTracked(2) : source
            @assert(picked.value == 12)
            @assert(source.value == 1)
            @assert(PostCopyCount == 1)
        }
        @assert(DropCount == 1)
    }
    @assert(DropCount == 2)
    @assert(DropTrace == 1201)
}

// Two lvalue arms: whichever wins is copied, the loser is not touched.
#test
{
    resetHooks()
    g_pick = false
    {
        var left  = makeTracked(3)
        var right = makeTracked(4)
        {
            let picked = g_pick ? left : right
            @assert(picked.value == 14)
            @assert(PostCopyCount == 1)
        }
        @assert(left.value == 3)
        @assert(right.value == 4)
        @assert(DropCount == 1)
    }
    @assert(DropCount == 3)
}

// 'var' binds the same way as 'let'.
#test
{
    resetHooks()
    g_pick = false
    {
        var source = makeTracked(6)
        {
            var picked = g_pick ? makeTracked(7) : source
            @assert(picked.value == 16)
            picked.value = 8
        }
        @assert(source.value == 6)
        @assert(PostCopyCount == 1)
        @assert(DropCount == 1)
        @assert(DropTrace == 8)
    }
    @assert(DropCount == 2)
}
