#global private

// ---------------------------------------------------------------------------
// Float math operations whose operand is proven to be a constant outside the
// operation's domain. Each is marked `#[Swag.Sanity(.Math, true)]` so the sanitizer
// runs (and catches it) in every build config; without that the runtime domain guard
// would panic where Math safety is on, or the operation would silently produce
// NaN where it is off.
// ---------------------------------------------------------------------------

// sqrt of a negative f32 constant.
#[Swag.Sanity(.Math, true)]
#test
{
    var x = -1.0'f32
    let y = @sqrt(x) // swc-expected-error {{sanity_err_invalid_argument}}
    discard y
}

// sqrt of a negative f64 constant.
#[Swag.Sanity(.Math, true)]
#test
{
    var x = -2.0'f64
    let y = @sqrt(x) // swc-expected-error {{sanity_err_invalid_argument}}
    discard y
}

// log of a negative value.
#[Swag.Sanity(.Math, true)]
#test
{
    var x = -1.0'f32
    let y = @log(x) // swc-expected-error {{sanity_err_invalid_argument}}
    discard y
}

// log10 of a negative value.
#[Swag.Sanity(.Math, true)]
#test
{
    var x = -5.0'f64
    let y = @log10(x) // swc-expected-error {{sanity_err_invalid_argument}}
    discard y
}

// asin outside [-1, 1].
#[Swag.Sanity(.Math, true)]
#test
{
    var x = 2.0'f32
    let y = @asin(x) // swc-expected-error {{sanity_err_invalid_argument}}
    discard y
}

// acos outside [-1, 1].
#[Swag.Sanity(.Math, true)]
#test
{
    var x = -3.0'f64
    let y = @acos(x) // swc-expected-error {{sanity_err_invalid_argument}}
    discard y
}

// ---------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// ---------------------------------------------------------------------------

// In-domain constants.
#test
{
    var x = 4.0'f32
    @assert(@sqrt(x) == 2.0'f32)
}

#[Swag.Sanity(.Math, true)]
#test
{
    var x = 1.0'f64
    @assert(@log(x) == 0.0'f64)
}

#[Swag.Sanity(.Math, true)]
#test
{
    var x = 0.5'f32
    let y = @asin(x)
    discard y
}

// Negative zero is not a domain error (`sqrt(-0.0) == -0.0`).
#[Swag.Sanity(.Math, true)]
#test
{
    var x = -0.0'f32
    let y = @sqrt(x)
    discard y
}

// An unknown (parameter) value is never assumed out of domain: no false positive.
func rootOf(v: f32)->f32
{
    return @sqrt(v)
}

#test
{
    @assert(rootOf(9.0'f32) == 3.0'f32)
}
