#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-787 - Out-of-bounds write
//
// The write sink. Kept apart from CWE-125 because a read folds into an addressing mode and a
// write does not, so the two reach the guard through different lowering.
//
// Swag: guarded wherever the destination carries a count. The raw memory intrinsics take a
// byte count unrelated to either operand and are not.
// -----------------------------------------------------------------------------

// --- Faults ---

#[Swag.Safety(.BoundCheck, true)]
func writeSlice(index: u64)
{
    var storage        = [0, 0, 0]
    var view: [..] s32 = storage
    view[index] = 1     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run writeSlice(opaqueU64(3))
}

// A loop whose bound is computed one element too far.
#[Swag.Safety(.BoundCheck, true)]
func fillPastEnd(count: u64)
{
    var storage: [4] s32
    for index in count do
        storage[index] = 1     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run fillPastEnd(opaqueU64(5))
}

// GAP compiler.safety.006 - 'Swag.memcpy' takes a byte count that has no relation to either
// operand, so writing more bytes than the destination holds is not judged. Left commented
// because it really does overwrite the frame.
//
// func memcpyPastEnd()
// {
//     var source:      [16] u8
//     var destination: [4] u8
//     Swag.memcpy(&destination[0], &source[0], source.count)     // writes 16 bytes into 4
// }

// --- Sound ---

func fillExactly()->s32
{
    var storage: [4] s32
    for index in storage.count do
        storage[index] = cast(s32) index
    return storage[3]
}

#test
{
    Swag.assert(fillExactly() == 3)
}
