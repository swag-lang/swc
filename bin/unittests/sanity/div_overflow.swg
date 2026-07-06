#global private

// ---------------------------------------------------------------------------
// `INT_MIN / -1` (and `INT_MIN % -1`) overflows and faults on x64. Marked
// `#[Swag.Sanity(.Overflow, true)]` so the sanitizer runs (and catches it) in every
// build config.
// ---------------------------------------------------------------------------

#[Swag.Sanity(.Overflow, true)]
#test
{
    var a = -2147483648's32
    var d = -1's32
    let x = a / d // swc-expected-error {{sanity_err_integer_overflow}}
    discard x
}

#[Swag.Sanity(.Overflow, true)]
#test
{
    var a = -2147483648's32
    var d = -1's32
    let x = a % d // swc-expected-error {{sanity_err_integer_overflow}}
    discard x
}

#[Swag.Sanity(.Overflow, true)]
#test
{
    var a = -9223372036854775808's64
    var d = -1's64
    let x = a / d // swc-expected-error {{sanity_err_integer_overflow}}
    discard x
}

// ---------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// ---------------------------------------------------------------------------

// INT_MIN divided by anything other than -1.
#[Swag.Sanity(.Overflow, true)]
#test
{
    var a = -2147483648's32
    var d = 2's32
    @assert(a / d == -1073741824)
}

// -1 divisor with a non-INT_MIN dividend.
#[Swag.Sanity(.Overflow, true)]
#test
{
    var a = 100's32
    var d = -1's32
    @assert(a / d == -100)
}
