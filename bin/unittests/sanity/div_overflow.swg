#global private

// ---------------------------------------------------------------------------
// `INT_MIN / -1` (and `INT_MIN % -1`) overflows and faults on x64. Marked
// `#[Swag.Sanity(.Overflow, true)]` so the sanitizer runs (and catches it) in every
// build config.
// ---------------------------------------------------------------------------

#[Swag.Sanity(.Overflow, true)]
#test
{
    var a = -2147483648_s32
    var d = -1_s32
    let x = a / d     // swc-expected-error {{sanity_err_integer_overflow}}
    discard x
}

#[Swag.Sanity(.Overflow, true)]
#test
{
    var a = -2147483648_s32
    var d = -1_s32
    let x = a % d     // swc-expected-error {{sanity_err_integer_overflow}}
    discard x
}

#[Swag.Sanity(.Overflow, true)]
#test
{
    var a = -9223372036854775808_s64
    var d = -1_s64
    let x = a / d     // swc-expected-error {{sanity_err_integer_overflow}}
    discard x
}

// A nonzero guard must retain the exact dividend, including when its low byte is zero.
#test
{
    var a = -2147483648_s32
    if a != 0
    {
        var d = -1_s32
        discard a / d     // swc-expected-error {{sanity_err_integer_overflow}}
    }
}

#test
{
    var a = -9223372036854775808_s64
    if a != 0
    {
        var d = -1_s64
        discard a % d     // swc-expected-error {{sanity_err_integer_overflow}}
    }
}

// ---------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// ---------------------------------------------------------------------------

// INT_MIN divided by anything other than -1.
#[Swag.Sanity(.Overflow, true)]
#test
{
    var a = -2147483648_s32
    var d = 2_s32
    Swag.require(a / d == -1073741824)
}

// -1 divisor with a non-INT_MIN dividend.
#[Swag.Sanity(.Overflow, true)]
#test
{
    var a = 100_s32
    var d = -1_s32
    Swag.require(a / d == -100)
}
