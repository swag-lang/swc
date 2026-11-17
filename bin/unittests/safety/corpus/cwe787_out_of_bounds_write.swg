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

#[Swag.Safety(.BoundCheck, true)]
func fillRangePastEnd()
{
    var storage: [4] s32
    for index in 0 to 4 do
        storage[index] = 1     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run fillRangePastEnd()
}

#[Swag.Safety(.BoundCheck, true)]
func fillRangeBeforeStart()
{
    var storage: [4] s32
    for index in -1 until 3 do
        storage[index] = 1     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run fillRangeBeforeStart()
}

#[Swag.Safety(.BoundCheck, true)]
func fillRangeWithChangedIndex()
{
    var storage: [4] s32
    for index in 0 until 4
    {
        index = 4
        storage[index] = 1     // swc-expected-error {{safety_err_runtime}}
    }
}

#test
{
    #run fillRangeWithChangedIndex()
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
        storage[index] = cast(s32, index)
    return storage[3]
}

func fillRangeExactly()->s32
{
    var storage: [4] s32
    for index in 0 until 4 do
        storage[index] = index
    return storage[3]
}

func fillRangeInclusive()->s32
{
    var storage: [4] s32
    for index in 1 to 3 do
        storage[index] = index
    return storage[3]
}

func fillRangeWithSafeChangedIndex()->s32
{
    var storage: [4] s32
    for index in 0 until 4
    {
        if index == 0 do
            index = 2
        storage[index] = index
    }
    return storage[2] + storage[3]
}

func sumRangeWithChangedNegativeIndex()->s32
{
    var sum = 0
    var changed = false
    for index in -1 to 1
    {
        if index == 0 && !changed
        {
            index = -2
            changed = true
        }
        sum += index
    }
    return sum
}

func firstWideRangeIndex()->s64
{
    for index in -1 to 2147483648 do
        return index
    return 0
}

func sumWideRangeIndices()->s64
{
    var sum: s64
    for index in 2147483647 until 2147483649 do
        sum += index
    return sum
}

#test
{
    Swag.require(fillExactly() == 3)
    Swag.require(fillRangeExactly() == 3)
    Swag.require(fillRangeInclusive() == 3)
    Swag.require(fillRangeWithSafeChangedIndex() == 5)
    Swag.require(sumRangeWithChangedNegativeIndex() == -3)
    Swag.require(firstWideRangeIndex() == -1)
    Swag.require(sumWideRangeIndices() == 4294967295)
}
