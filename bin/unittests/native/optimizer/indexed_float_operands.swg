#global private

// A float element loaded at an indexed address folds into the arithmetic
// that reads it. Sums, differences, products and quotients over f32 and f64
// arrays, at an offset from the index too, must match the unfolded loops.

#[Swag.Optimize(true), Swag.NoInline]
func dotF(a, b: const [*] f32, n: u64)->f32
{
    var s = 0.0'f32
    for i in n do s += a[i] * b[i]
    return s
}
#[Swag.Optimize(false), Swag.NoInline]
func dotFRef(a, b: const [*] f32, n: u64)->f32
{
    var s = 0.0'f32
    for i in n do s += a[i] * b[i]
    return s
}

#[Swag.Optimize(true), Swag.NoInline]
func diffNext(d: [*] f64, a: const [*] f64, n: u64)
{
    for i in n do d[i] = a[i] - a[i + 1]
}
#[Swag.Optimize(false), Swag.NoInline]
func diffNextRef(d: [*] f64, a: const [*] f64, n: u64)
{
    for i in n do d[i] = a[i] - a[i + 1]
}

#[Swag.Optimize(true), Swag.NoInline]
func ratios(d: [*] f32, a, b: const [*] f32, n: u64)
{
    for i in n do d[i] = a[i] / b[i] + b[i]
}
#[Swag.Optimize(false), Swag.NoInline]
func ratiosRef(d: [*] f32, a, b: const [*] f32, n: u64)
{
    for i in n do d[i] = a[i] / b[i] + b[i]
}

#test
{
    let a: [6] f32 = [1.5, -2, 3.25, 4, -0.5, 8]
    let b: [6] f32 = [2, 0.25, -1, 3, 5, -4]
    Swag.assert(dotF(&a[0], &b[0], 6) == dotFRef(&a[0], &b[0], 6))

    let w:  [6] f64 = [1, 4, 9, 16, 25, 36]
    var d1: [5] f64
    var d2: [5] f64
    diffNext(&d1[0], &w[0], 5)
    diffNextRef(&d2[0], &w[0], 5)
    for i in 5 do
        Swag.assert(d1[i] == d2[i])

    var r1: [6] f32
    var r2: [6] f32
    ratios(&r1[0], &a[0], &b[0], 6)
    ratiosRef(&r2[0], &a[0], &b[0], 6)
    for i in 6 do
        Swag.assert(r1[i] == r2[i])
}
