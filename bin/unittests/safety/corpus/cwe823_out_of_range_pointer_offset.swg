#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-823 - Use of out-of-range pointer offset
//
// The pointer itself is computed out of range, before any dereference.
//
// Swag: a '[*] T' is the pointer-arithmetic type and it carries neither provenance nor
// extent, so no rule applies to it. This is the sharpest edge of the language's unsafe
// surface and the whole file below is a gap: every fault here is silent in every
// configuration.
//
// Note what is NOT here: a plain '*T' has no arithmetic at all, so reaching this class needs
// a deliberate 'cast([*] T)'. The cast is the marker the language does not yet ask for.
// -----------------------------------------------------------------------------

// --- Faults ---

// GAP compiler.safety.006 - walking a block pointer past its allocation, then reading. No
// static proof and no runtime guard. Left commented because it really does read out of
// bounds and would take the compiler's own heap with it.
//
// func walkPastEnd(steps: u64)->s32
// {
//     var values = [10, 20, 30]
//     var cursor = cast([*] s32) &values[0]
//     cursor = cursor + steps
//     return cursor[0]
// }
//
// #test
// {
//     Swag.assert(walkPastEnd(opaqueU64(100)) == 0)
// }

// GAP compiler.safety.006 - indexing a block pointer with any offset is unchecked, whether
// or not the pointer itself moved.
//
// func indexFarPastEnd(index: u64)->s32
// {
//     var values = [10, 20, 30]
//     let cursor = cast([*] s32) &values[0]
//     return cursor[index]
// }

// GAP compiler.safety.006 - an integer becomes a pointer with no ceremony, which is the
// widest of all the routes: nothing about the value has to have come from an allocation.
//
// func forgePointer(address: u64)->s32
// {
//     let pointer = cast(*s32) address
//     return pointer[]
// }

// --- Sound ---

// Walking a block pointer inside the buffer it came from is what the type is for, and it
// stays silent - the corpus must not claim the language rejects pointer arithmetic.
func walkInsideBuffer()->s32
{
    var values = [10, 20, 30]
    var cursor = cast([*] s32) &values[0]
    cursor = cursor + 2
    return cursor[0]
}

#test
{
    Swag.assert(walkInsideBuffer() == 30)
}

// Taking the address of an element yields a single-object pointer, which has no arithmetic:
// the element address cannot silently become a walk.
func elementAddressIsSingleObject()->s32
{
    var values = [10, 20, 30]
    let pointer = &values[1]
    #assert(#typeof(pointer) == *s32)
    return pointer[]
}

#test
{
    Swag.assert(elementAddressIsSingleObject() == 20)
}
