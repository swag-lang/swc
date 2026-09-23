#global private

// Swag's own convention passes float arguments in xmm0-xmm5, past the four
// lanes the platform C ABI shares between the integer and float files. The
// lanes past the fourth are the ones a change to that rule breaks first, so
// each of these reads every argument back and mixes integers in between.

#[Swag.NoInline]
func sum6d(a, b, c, d, e, f: f64)->f64
{
    return a * 1.0 + b * 10.0 + c * 100.0 + d * 1000.0 + e * 10000.0 + f * 100000.0
}

#[Swag.NoInline]
func sum8d(a, b, c, d, e, f, g, h: f64)->f64
{
    return sum6d(a, b, c, d, e, f) + g * 1000000.0 + h * 10000000.0
}

#[Swag.NoInline]
func mixed(a: f64, i: s32, b: f64, j: s32, c: f64, d: f64, e: f64, k: s32)->f64
{
    return a + b * 10.0 + c * 100.0 + d * 1000.0 + e * 10000.0 + cast(f64) (i + j * 10 + k * 100)
}

#[Swag.NoInline]
func sum6f(a, b, c, d, e, f: f32)->f32
{
    return a * 1.0 + b * 10.0 + c * 100.0 + d * 1000.0 + e * 10000.0 + f * 100000.0
}

#test
{
    Swag.assert(sum6d(1, 2, 3, 4, 5, 6) == 654321.0)
    Swag.assert(sum8d(1, 2, 3, 4, 5, 6, 7, 8) == 87654321.0)
    Swag.assert(mixed(1, 2, 3, 4, 5, 6, 7, 8) == 76531.0 + 842.0)
    Swag.assert(sum6f(1, 2, 3, 4, 5, 6) == 654321.0)
}

// The same contract through a function value, which the code generator lowers
// with the convention of the pointed-to function rather than the caller's.
alias Sum6 = func(f64, f64, f64, f64, f64, f64)->f64

#test
{
    let fn: Sum6 = &sum6d
    Swag.assert(fn(1, 2, 3, 4, 5, 6) == 654321.0)
}

// And through a lambda, so the closure path sees the same lanes.
#test
{
    let fn = func(a, b, c, d, e, f: f64)->f64 { return sum6d(a, b, c, d, e, f) }
    Swag.assert(fn(6, 5, 4, 3, 2, 1) == 123456.0)
}
