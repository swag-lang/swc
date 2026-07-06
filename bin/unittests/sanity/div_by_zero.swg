#global private

// ---------------------------------------------------------------------------
// Provable integer division / modulo by zero. Each is marked
// `#[Swag.Sanity(.Math, true)]` so the sanitizer runs (and catches it) in every build
// config, including fast-compile where the sanity checks are off by default.
// ---------------------------------------------------------------------------

// Division by a variable proven to be zero.
#[Swag.Sanity(.Math, true)]
#test
{
    var d = 0
    var a = 10
    let x = a / d // swc-expected-error {{sanity_err_division_zero}}
    discard x
}

// Modulo by a variable proven to be zero.
#[Swag.Sanity(.Math, true)]
#test
{
    var d = 0
    var a = 10
    let x = a % d // swc-expected-error {{sanity_err_division_zero}}
    discard x
}

// The zero value propagates through a copy.
#[Swag.Sanity(.Math, true)]
#test
{
    var d = 0
    var e = d
    var a = 10
    let x = a / e // swc-expected-error {{sanity_err_division_zero}}
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
    @assert(a / d == 2)
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
    @assert(safeDivide(10, 5) == 2)
    @assert(safeDivide(10, 0) == 0)
}
