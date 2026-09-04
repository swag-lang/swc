#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-129 - Improper validation of array index
//
// The program DOES check the index, and the check is wrong. This is the class that matters
// most in practice: the fault is not a missing test but a test against the wrong bound.
//
// Swag: the guard is the backstop. A validation bug does not become a memory fault, it
// becomes a panic at the access the wrong test let through.
// -----------------------------------------------------------------------------

// --- Faults ---

// '>' where '>=' was meant: the classic. The validation passes, the access does not.
#[Swag.Safety(.BoundCheck, true)]
func validatedWithWrongComparison(index: u64)->s32
{
    var values = [10, 20, 30]
    if index > values.count do
        return -1
    return values[index]     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run validatedWithWrongComparison(opaqueU64(3))
}

// The index is validated against a DIFFERENT container than the one indexed.
#[Swag.Safety(.BoundCheck, true)]
func validatedAgainstWrongContainer(index: u64)->s32
{
    var large = [1, 2, 3, 4, 5]
    var small = [1, 2]
    if index >= large.count do
        return -1
    return small[index]     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run validatedAgainstWrongContainer(opaqueU64(2))
}

// --- Sound ---

func validatedCorrectly(index: u64)->s32
{
    var values = [10, 20, 30]
    if index >= values.count do
        return -1
    return values[index]
}

#test
{
    Swag.assert(validatedCorrectly(2) == 30)
    Swag.assert(validatedCorrectly(3) == -1)
}
