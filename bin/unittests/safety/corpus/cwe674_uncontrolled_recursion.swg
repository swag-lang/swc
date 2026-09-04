#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-674 - Uncontrolled recursion
//
// The frame chain grows until the stack is exhausted.
//
// Swag: a LARGE frame is handled correctly - the prologue emits the Windows guard-page probes,
// so a single function cannot step over the guard page and land in unrelated memory (the
// "stack clash" form). Running out of depth is reported: every thread that runs user code
// claims a stack reserve up front, so the fault reporter has a frame of its own to run in and
// names the fault instead of dying on the exhausted stack.
// -----------------------------------------------------------------------------

// --- Faults ---

// Exhausting the stack is reported as EXCEPTION_STACK_OVERFLOW, with the task state and the
// faulting function. The case is not run here because it ends the process by design - what it
// must not do, and no longer does, is end it in silence.
//
// func recurseForever(depth: s32)->s32
// {
//     var frame: [4096] u8
//     frame[0] = 1
//     return recurseForever(depth + 1) + cast(s32) frame[0]
// }

// --- Sound ---

// A bounded recursion is ordinary code and must stay silent.
func sumDown(depth: s32)->s32
{
    if depth <= 0 do
        return 0
    return depth + sumDown(depth - 1)
}

// A large frame is probed page by page in the prologue, so growing the stack by more than one
// page cannot skip the guard page. This is the stack-clash half, and it is covered.
func largeFrame(index: u64)->u8
{
    var frame: [64 * 1024] u8
    frame[index] = 7
    return frame[index]
}

#test
{
    Swag.assert(sumDown(opaqueS32(10)) == 55)
    Swag.assert(largeFrame(opaqueU64(40000)) == 7)
}
