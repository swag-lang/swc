#global private

// 'return local' transfers ownership out of the function: the value is bit-copied into
// the caller's storage, 'opPostMove' restores its invariants there, and the local's
// scope-exit drop is elided, so the resource is released exactly once, by the caller.
// Only a local observed by a 'defer' body or a closure cannot move: the return then
// deep-copies ('opPostCopy') and the local drops normally.
//
// 'Tracked' carries padding so it returns through the indirect (sret) path, which is
// where the copy and its lifecycle hook run. 'SmallTracked' fits a register: that
// direct path transfers the bits without any hook and still elides the local's drop.
//
// Every maker reads the mutable 'g_seed' so the calls cannot be constant-folded: the
// hook counters must be observable at runtime.

var DropCount:     u32 = 0
var DropTrace:     s64 = 0
var PostCopyCount: u32 = 0
var PostMoveCount: u32 = 0
var g_seed:        s32 = 0
var g_sink:        s32 = 0
var g_cond             = true

func resetHooks(seed: s32)
{
    DropCount     = 0
    DropTrace     = 0
    PostCopyCount = 0
    PostMoveCount = 0
    g_seed        = seed
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
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
    }
}

struct SmallTracked
{
    value: s32 = 5
}

impl SmallTracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64) .value
    }
}

// A releasable resource without 'opPostCopy': the shape that used to dangle, because
// the old return copied the bits and still dropped the local.
struct Resource
{
    id:  s32
    pad: [3] s64
}

impl Resource
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64) .id
    }
}

func fillResource(res: *Resource, id: s32)
{
    res.id = id
}

func makeResource()->Resource
{
    var result: Resource
    fillResource(&result, g_seed)
    return result
}

func makeTracked()->Tracked
{
    var result: Tracked
    result.value = g_seed
    return result
}

func forwardTracked()->Tracked
{
    return makeTracked()
}

func makeTrackedBranch()->Tracked
{
    var result: Tracked
    result.value = g_seed
    if g_cond do
        return result
    g_sink = result.value
    return result
}

func makeTrackedDeferred()->Tracked
{
    var result: Tracked
    result.value = g_seed
    defer g_sink = result.value
    return result
}

func makeSmallTracked()->SmallTracked
{
    var result: SmallTracked
    result.value = g_seed
    return result
}

// 'NoInline' pins the sret path: this maker exists to observe the real return slot.
#[Swag.NoInline]
func makeTrackedRetval()->Tracked
{
    var result: retval
    result.value = g_seed
    return result
}

#[Swag.Inline]
func makeTrackedInline()->Tracked
{
    var result: Tracked
    result.value = g_seed
    return result
}

var g_Template = Tracked{41, 0, 0}

#[Swag.Inline]
func readTemplateInline()->Tracked
{
    return g_Template
}

// A drop-only local moves out: released exactly once, by the caller, with the bits intact.
#test
{
    resetHooks(7)
    {
        var x = makeResource()
        Swag.assert(x.id == 7)
    }
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 7)
}

// A full-lifecycle local runs 'opPostMove' on the way out, never 'opPostCopy'.
#test
{
    resetHooks(9)
    {
        var x = makeTracked()
        Swag.assert(x.value == 9)
    }
    Swag.assert(PostMoveCount == 1)
    Swag.assert(PostCopyCount == 0)
    Swag.assert(DropCount == 1)
}

// Forwarding an owned call result moves it again instead of deep-copying it.
#test
{
    resetHooks(11)
    {
        var x = forwardTracked()
        Swag.assert(x.value == 11)
    }
    Swag.assert(PostCopyCount == 0)
    Swag.assert(DropCount == 1)
}

// Each return site moves independently, branch or not.
#test
{
    resetHooks(13)
    g_cond = true
    {
        var x = makeTrackedBranch()
        Swag.assert(x.value == 13)
    }
    Swag.assert(PostCopyCount == 0)
    Swag.assert(DropCount == 1)

    resetHooks(17)
    g_cond = false
    {
        var x = makeTrackedBranch()
        Swag.assert(x.value == 17)
    }
    Swag.assert(g_sink == 17)
    Swag.assert(PostCopyCount == 0)
    Swag.assert(DropCount == 1)
}

// A 'defer' still observes the local after the return: the value is copied out and the
// local keeps its normal scope-exit drop.
#test
{
    resetHooks(19)
    g_sink = 0
    {
        var x = makeTrackedDeferred()
        Swag.assert(x.value == 19)
    }
    Swag.assert(g_sink == 19)
    Swag.assert(PostCopyCount == 1)
    Swag.assert(DropCount == 2)
}

// A register-returned struct transfers its bits without any hook; the local's drop is
// still elided, so ownership stays single.
#test
{
    resetHooks(21)
    {
        var x = makeSmallTracked()
        Swag.assert(x.value == 21)
    }
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 21)
}

// A 'retval' local is built straight in the caller's slot: returning it runs no hook
// at all — no copy, no move, and the only drop is the caller's. The return used to
// copy the slot onto itself and run 'opPostCopy' on it, duplicating the ownership the
// slot already held.
#test
{
    resetHooks(27)
    {
        var x = makeTrackedRetval()
        Swag.assert(x.value == 27)
    }
    Swag.assert(PostMoveCount == 0)
    Swag.assert(PostCopyCount == 0)
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 27)
}

// An inlined return moves the local out: 'opPostMove' runs into the result slot and
// the local's drop is elided. When the expansion is a real call (for example when
// backend optimization is disabled) the consumer copy disappears, so only the ownership invariants are pinned:
// one move out, at most one consumer copy, one drop.
#test
{
    resetHooks(23)
    {
        var x = makeTrackedInline()
        Swag.assert(x.value == 23)
    }
    Swag.assert(PostMoveCount == 1)
    Swag.assert(PostCopyCount <= 1)
    Swag.assert(DropCount == 1)
}

// An inlined return of a live lvalue deep-copies it: the source stays untouched, no
// move runs, and only the declared variable is dropped. The number of copies depends
// on whether the expansion is a real call (for example when backend optimization is disabled).
#test
{
    resetHooks(0)
    {
        var x = readTemplateInline()
        Swag.assert(x.value == 41)
        x.value = 1
    }
    Swag.assert(g_Template.value == 41)
    Swag.assert(PostCopyCount >= 1)
    Swag.assert(PostMoveCount == 0)
    Swag.assert(DropCount == 1)
    Swag.assert(DropTrace == 1)
}

// Ownership stays one-to-one across repeated calls.
#test
{
    resetHooks(3)
    for 8
    {
        var x = makeResource()
        g_sink += x.id
    }
    Swag.assert(DropCount == 8)
}
