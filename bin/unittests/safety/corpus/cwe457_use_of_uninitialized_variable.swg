#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-457 - Use of uninitialized variable
//
// A read observes storage that was never written. In C this is the single most common source
// of non-reproducible behavior, because the value depends on what the frame held before.
//
// Swag: eliminated by construction, and this is one of the two places where the language is
// strictly ahead of Rust in usability rather than merely level with it. There is NO
// source-level escape hatch for uninitialized storage - no 'undefined', no '---', nothing.
// Every declaration begins at its type's safe default, and the compiler may only elide that
// initialization after proving it cannot be observed. Where a type has no safe default,
// definite-assignment rejects the read instead.
//
// So this file has no runnable fault: the class cannot be written down. What it pins is that
// the defaults really are observable, since the whole guarantee rests on it.
// -----------------------------------------------------------------------------

// --- Faults ---

// The only reachable form of the class: a type with no safe default, read before assignment.
// Definite-assignment rejects it at compile time.
struct NeedsInitialization
{
    pointer: *s32
}

// NO GAP. There is no spelling of "give me this storage without initializing it", so the
// C form of CWE-457 has no Swag equivalent to write here. If an escape hatch is ever added,
// its abuse belongs in this file.

// --- Sound ---

func defaultsAreObservable()->bool
{
    var flag:    bool
    var number:  f64
    var pointer: *u8?
    var text:    string?
    var buffer:  [4] s32

    return !flag and number == 0 and pointer == null and text == null and buffer[3] == 0
}

// The default survives even when every field is overwritten right after, which is what makes
// the elision an optimization rather than a semantic.
struct Point
{
    x, y: s32
}

func fieldsStartAtZero()->s32
{
    var point: Point
    let before = point.x + point.y
    point.x = 1
    point.y = 2
    return before + point.x + point.y
}

// A local declared in a loop body starts fresh on every turn, rather than keeping what the
// previous turn left in the same slot.
func loopLocalIsFreshEveryTurn()->s32
{
    var total = 0's32
    for turn in 3
    {
        var accumulated: s32
        accumulated += cast(s32) turn
        total       += accumulated
    }

    return total
}

#test
{
    Swag.assert(defaultsAreObservable())
    Swag.assert(fieldsStartAtZero() == 3)
    Swag.assert(loopLocalIsFreshEveryTurn() == 3)
}
