#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-416 - Use after free
//
// The pointer is read after the memory it addresses has been released.
//
// Swag: a compile-time proof, not a guard. The analysis infers which functions FREE what
// their parameters point at - the summary is seeded by a call reaching 'Swag.IAllocator.free'
// and chains through wrappers and across modules - then marks the slot at the call site. It
// is a must-analysis: an alias or a conditional release is a miss, never a false positive.
//
// The misses below are the ones that matter, because they are the shapes real code has.
// -----------------------------------------------------------------------------

// --- Faults ---

#[Swag.Sanity(.Lifecycle, true)]
func readAfterFree()->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    pointer[] = 1
    heapFree(pointer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return pointer[]     // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    #run readAfterFree()
}

#[Swag.Sanity(.Lifecycle, true)]
func writeAfterFree()
{
    let pointer = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    pointer[] = 2     // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    #run writeAfterFree()
}

// The release goes through one more wrapper, which inherits the summary through the fixpoint
// that chains them. Note the absence of '#run' here: the summaries are final only once the
// module is drained, so a body forced through the compile-time JIT before that is judged
// against summaries that are still growing (compiler.safety.016). Reaching the body the
// ordinary way is what exercises the rule.
#[Swag.Sanity(.Lifecycle, true)]
func releaseWrapper(pointer: *s32)
{
    heapFree(pointer, 4)
}

#[Swag.Sanity(.Lifecycle, true)]
func readAfterWrappedFree()->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    releaseWrapper(pointer)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return pointer[]     // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readAfterWrappedFree()
}

// --- Known misses ---

// GAP compiler.safety.003 - an offset read after the free is not judged: the check only
// looks at a plain dereference, not at a base+offset or an indexed load. This is the shape
// almost every real use-after-free has, since a freed object is usually read through a
// field or an element. Left commented because it really does read released memory.
//
// struct Node { first, second: s32 }
//
// #[Swag.Sanity(.Lifecycle, true)]
// func readFieldAfterFree()->s32
// {
//     let node = cast(*Node) heapAlloc(8)
//     node.second = 1
//     heapFree(node, 8)
//     return node.second     // expected: sanity_err_use_after_free
// }

// GAP compiler.safety.003 - a cast on the freed argument loses the origin slot, so the
// pointer is not marked at all and the later read is silent.
//
// #[Swag.Sanity(.Lifecycle, true)]
// func readAfterCastFree()->s32
// {
//     let block = cast([*] void) heapAlloc(4)
//     let value = cast(*s32) block
//     value[] = 1
//     heapFree(cast(*void) block, 4)
//     return value[]     // expected: sanity_err_use_after_free
// }

// --- Sound: documented misses that must stay silent ---

// An alias is a miss BY DESIGN: the analysis is a must-analysis, and reporting here would
// need to prove the two names address the same block.
#[Swag.Sanity(.Lifecycle, true)]
func readThroughAlias()->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    let other   = pointer
    pointer[] = 1
    heapFree(pointer, 4)
    return other[]
}

// Reassigning the pointer makes it live again, and the analysis must see that.
#[Swag.Sanity(.Lifecycle, true)]
func reassignedAfterFree()->s32
{
    var pointer = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)
    pointer = cast(*s32) heapAlloc(4)
    pointer[] = 7
    let value = pointer[]
    heapFree(pointer, 4)
    return value
}

// A release on one path only cannot be proven, so nothing is reported.
#[Swag.Sanity(.Lifecycle, true)]
func conditionalFree(release: bool)->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    pointer[] = 3
    if release do
        heapFree(pointer, 4)
    return pointer[]
}

#test
{
    discard readThroughAlias()
    Swag.assert(reassignedAfterFree() == 7)
    Swag.assert(conditionalFree(opaqueBool(false)) == 3)
}
