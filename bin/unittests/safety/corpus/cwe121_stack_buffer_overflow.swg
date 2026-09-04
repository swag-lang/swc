#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-121 - Stack-based buffer overflow
//
// A write or a read reaches past the end of a buffer that lives in the frame.
//
// Swag: a constant index is a static error in every configuration; a computed one is a
// runtime panic wherever '.BoundCheck' is on.
//
// Each case names ONE layer. A case aimed at the static proof turns the runtime guard off,
// so the guard cannot answer for it; a case aimed at the guard launders its index through
// an opaque call, so the proof cannot. Otherwise the corpus cannot say which half worked.
// -----------------------------------------------------------------------------

// --- Faults ---

// The index is a constant the value analysis folds: proven before the program runs.
#[Swag.Safety(.BoundCheck, false), Swag.Sanity(.BoundCheck, true)]
func stackWriteConstant()
{
    var buffer: [8] u8
    buffer[8] = 1     // swc-expected-error {{sanity_err_out_of_bounds}}
}

#test
{
    #run stackWriteConstant()
}

// The index only exists at run time, so the guard is what answers.
#[Swag.Safety(.BoundCheck, true)]
func stackWriteComputed(index: u64)
{
    var buffer: [8] u8
    buffer[index] = 1     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run stackWriteComputed(opaqueU64(8))
}

// One past the end of a two-dimensional buffer.
#[Swag.Safety(.BoundCheck, true)]
func stackWriteGrid(row, column: u64)
{
    var grid: [2, 3] s32
    grid[row, column] = 1     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run stackWriteGrid(opaqueU64(1), opaqueU64(3))
}

// --- Sound ---

func stackWriteInRange()->u8
{
    var buffer: [8] u8
    for index in buffer.count do
        buffer[index] = cast(u8) index
    return buffer[7]
}

#test
{
    Swag.assert(stackWriteInRange() == 7)
}
