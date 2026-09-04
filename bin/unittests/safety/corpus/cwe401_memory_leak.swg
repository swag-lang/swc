#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-401 - Missing release of memory after effective lifetime
//
// The last pointer to an allocation is dropped without releasing it. This is
// 'valid-memtrack' in SV-COMP terms, the third of the three memory-safety sub-properties.
//
// Swag: NOT MODELLED. Nothing in the language or the tooling tracks whether an allocation is
// released - not the borrow rules, not the lifetime proofs, not a runtime guard. 'opDrop'
// gives a type a place to release what it owns, and nothing checks that a type which
// allocates has one, or that the value is ever dropped.
//
// The whole fault section of this file is therefore a gap. It is kept as one file rather than
// folded away because a corpus that silently omits the class it does not cover is not a
// measurement.
// -----------------------------------------------------------------------------

// --- Faults (none of these is reported, in any configuration) ---

// GAP compiler.safety.017 - the allocation is never released and the pointer dies with the
// frame. Leaks do not corrupt memory, so unlike the other gaps this one is safe to RUN: it
// is left live and merely leaks, which is exactly the point being pinned.
#[Swag.Sanity(.Lifecycle, true)]
func leakOnEveryPath()
{
    let pointer = cast(*s32) heapAlloc(4)
    pointer[] = 1
    // no heapFree: not reported
}

// GAP compiler.safety.017 - released on one path only, which is the shape a real leak has.
#[Swag.Sanity(.Lifecycle, true)]
func leakOnOnePath(release: bool)
{
    let pointer = cast(*s32) heapAlloc(4)
    pointer[] = 1
    if release do
        heapFree(pointer, 4)
    // the other path leaks: not reported
}

// GAP compiler.safety.017 - the pointer is overwritten before it is released, which loses
// the only reference to the first block.
#[Swag.Sanity(.Lifecycle, true)]
func leakByOverwrite()
{
    var pointer = cast(*s32) heapAlloc(4)
    pointer     = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)
    // the first block is unreachable and unreleased: not reported
}

// GAP compiler.safety.017 - a type that owns an allocation is not required to have an
// 'opDrop', so forgetting one leaks every instance and nothing says so.
//
// Also blocked by compiler.core.029: in 'release' this exact shape - a cross-file call
// assigned into a struct field - trips a compiler assertion. Uncomment when that entry
// closes; the three cases above cover the same class meanwhile.
//
// struct LeakyOwner
// {
//     pointer: *s32?
// }
//
// #[Swag.Sanity(.Lifecycle, true)]
// func leakThroughOwnerWithoutDrop()
// {
//     var owner: LeakyOwner
//     owner.pointer = cast(*s32) heapAlloc(4)
//     // 'LeakyOwner' has no 'opDrop': not reported
// }

#test
{
    leakOnEveryPath()
    leakOnOnePath(opaqueBool(false))
    leakByOverwrite()
}

// --- Sound ---

// The shape that does release, so a future rule has a negative to stay silent on.
#[Swag.Sanity(.Lifecycle, true)]
func releasedOnEveryPath(early: bool)->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    pointer[] = 1
    if early
    {
        heapFree(pointer, 4)
        return 0
    }

    let value = pointer[]
    heapFree(pointer, 4)
    return value
}

// A type whose 'opDrop' releases what it owns, dropped at the end of the scope.
struct TidyOwner
{
    pointer: *s32?
}

impl TidyOwner
{
    mtd opDrop()
    {
        if .pointer != null do
            heapFree(.pointer!, 4)
        .pointer = null
    }
}

func ownerReleasesOnDrop()->s32
{
    var owner: TidyOwner
    owner.pointer  = cast(*s32) heapAlloc(4)
    owner.pointer![] = 5
    return owner.pointer![]
}

#test
{
    Swag.assert(releasedOnEveryPath(opaqueBool(false)) == 1)
    Swag.assert(releasedOnEveryPath(opaqueBool(true)) == 0)
    Swag.assert(ownerReleasesOnDrop() == 5)
}
