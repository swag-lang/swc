#global private

// ---------------------------------------------------------------------------
// Provable integer division / modulo by zero. Each is marked
// `#[Swag.Sanity(.Math, true)]` so the sanitizer runs (and catches it) whatever the
// surrounding configuration says.
//
// The RUNTIME guard is turned off in the same breath, and that is not incidental. The guard
// lowers to a test of the divisor against zero, and the sanitizer narrows on exactly that
// kind of branch: past it, the divisor is no longer provably zero, so the guard would answer
// first and the static proof would have nothing left to say. One fault gets one report, from
// whichever layer is enabled - the static one where the guards are off, which is what
// `release` is, and the guard where they are on. These tests are about the static one.
// ---------------------------------------------------------------------------

// Division by a variable proven to be zero.
#[Swag.Safety(.Math, false), Swag.Sanity(.Math, true)]
#test
{
    var d = 0
    var a = 10
    let x = a / d     // swc-expected-error {{sanity_err_division_zero}}
    discard x
}

// Modulo by a variable proven to be zero.
#[Swag.Safety(.Math, false), Swag.Sanity(.Math, true)]
#test
{
    var d = 0
    var a = 10
    let x = a % d     // swc-expected-error {{sanity_err_division_zero}}
    discard x
}

// The zero value propagates through a copy.
#[Swag.Safety(.Math, false), Swag.Sanity(.Math, true)]
#test
{
    var d = 0
    var e = d
    var a = 10
    let x = a / e     // swc-expected-error {{sanity_err_division_zero}}
    discard x
}

// ---------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// ---------------------------------------------------------------------------

// Non-zero divisor.
#test
{
    var d = 5
    var a = 10
    Swag.assert(a / d == 2)
}

// The guard proves the divisor is non-zero on the dividing branch.
func safeDivide(a, d: s32)->s32
{
    if d != 0
    {
        return a / d
    }
    return 0
}

#test
{
    Swag.assert(safeDivide(10, 5) == 2)
    Swag.assert(safeDivide(10, 0) == 0)
}
