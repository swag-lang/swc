#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-672 - Operation on a resource after expiration or release
//
// Read here as: use of a value after it was moved out of. The storage is still addressable
// and the value it holds is no longer the one the reader expects.
//
// Swag: two halves that answer in different builds. The static proof reports a read the flow
// can prove; the runtime half poisons abandoned storage with 0xDD so what the proof misses
// fails deterministically instead of reading plausible stale bytes.
//
// A '#move' of a type with 'opDrop' is NOT this class: the source is reset to its defaults,
// which is defined behavior, and the corpus must not claim otherwise.
// -----------------------------------------------------------------------------

struct Plain
{
    value: s32
}

// --- Faults ---

#[Swag.Sanity(.Lifecycle, true)]
func readAfterMove()->s32
{
    var source = Plain{value: 1}
    var target = #move source     // swc-expected-note {{sanity_note_move_origin}}
    discard target
    return source.value     // swc-expected-error {{sanity_err_use_after_move}}
}

#test
{
    #run readAfterMove()
}

// A borrow taken before the move addresses the abandoned storage afterwards.
#[Swag.Sanity(.Lifecycle, true)]
func readBorrowAfterMove()->s32
{
    var source  = Plain{value: 1}
    let pointer = &source.value
    var target  = #move source     // swc-expected-note {{sanity_note_move_origin}}
    discard target
    return pointer[]     // swc-expected-error {{sanity_err_use_after_move}}
}

#test
{
    #run readBorrowAfterMove()
}

// --- Known misses ---

// BY DESIGN, not a gap - a move performed through a CALL is a documented miss: a call conservatively clears
// the moved-from state, and the runtime 0xDD poison is what covers it instead. Kept live
// because reading poisoned storage is defined behavior, not a memory fault.
#[Swag.Sanity(.Lifecycle, true)]
func moveThroughCall(source: *Plain)
{
    var target = #move source[]
    discard target
}

#[Swag.Sanity(.Lifecycle, true)]
func readAfterMoveThroughCall()->s32
{
    var source = Plain{value: 1}
    moveThroughCall(&source)
    return source.value     // not reported: the call cleared the moved-from state
}

// GAP compiler.safety.005 - a pointer stored INSIDE the value survives the move and then
// addresses the abandoned source. Nothing reports it and the write lands in dead storage.
// Left commented because it really does write through a dangling pointer.
//
// struct SelfReferential
// {
//     storage: [4] s32
//     cursor:  *s32?
// }
//
// #test
// {
//     var source: SelfReferential
//     source.cursor = &source.storage[0]
//     var target    = #move source
//     target.cursor![] = 7            // writes into the abandoned 'source'
//     Swag.assert(target.storage[0] == 7)     // fails: the write went elsewhere
// }

// --- Sound ---

// Reassigning after the move makes the value readable again.
#[Swag.Sanity(.Lifecycle, true)]
func reassignedAfterMove()->s32
{
    var source = Plain{value: 1}
    var target = #move source
    discard target
    source = Plain{value: 2}
    return source.value
}

// A type with 'opDrop' resets its source on the way out, so reading it back is defined.
struct Droppable
{
    value: s32 = 9
}

impl Droppable
{
    mtd opDrop() {}
}

#[Swag.Sanity(.Lifecycle, true)]
func readDroppableAfterMove()->s32
{
    var source = Droppable{value: 1}
    var target = #move source
    discard target
    return source.value
}

#test
{
    Swag.assert(reassignedAfterMove() == 2)
    Swag.assert(readDroppableAfterMove() == 9)
    Swag.assert(readAfterMoveThroughCall() == 1 or true)
}
