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
// "stack clash" form). What is missing is what happens when the guard page is finally hit:
// the process ends with no message and exit code 0, and under the compile-time JIT it takes
// the compiler with it.
//
// So the memory-safety half is covered and the diagnosis half is not. The fault cases are
// commented because running them ends the process.
// -----------------------------------------------------------------------------

// --- Faults ---

// GAP compiler.safety.012 - exhausting the stack produces neither a value, nor a panic, nor a
// message. It is the only class in this corpus where the language leaves no evidence at all.
//
// func recurseForever(depth: s32)->s32
// {
//     var frame: [4096] u8
//     frame[0] = 1
//     return recurseForever(depth + 1) + cast(s32) frame[0]
// }
//
// #test
// {
//     discard recurseForever(0)
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
