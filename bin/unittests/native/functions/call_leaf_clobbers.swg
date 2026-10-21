#global private
#global #[Swag.Safety(.Overflow, false)]

// An optimized caller keeps values across a call in the transient registers its leaf callee
// leaves alone. Many values live across leaf calls in a loop must come out as they would from
// an unoptimized copy of the same body, which trusts no callee.

#[Swag.NoInline]
func mixBits(a, b: u64)->u64 => (a ^ (b << 7)) + 0x9E37_79B9

#[Swag.NoInline]
func halve(a: f64)->f64 => a * 0.5 + 1.0

#[Swag.Optimize(true), Swag.NoInline]
func churn(count: u64)->u64
{
    var h0      = 1'u64
    var h1      = 3'u64
    var h2      = 5'u64
    var h3      = 7'u64
    var h4      = 11'u64
    var h5      = 13'u64
    var f0: f64 = 0.25
    var f1: f64 = 2.5
    var f2: f64 = 8.0
    for i in count
    {
        h0 = mixBits(h0, i)
        h1 += h0 ^ h5
        f0 = halve(f0 + f2)
        h2 = mixBits(h2 ^ h1, h3)
        h3 += h2 * h4
        f1 += f0 * f2
        h4 ^= mixBits(h3, h0)
        h5 += h4 + cast(u64, f1)
        f2 = halve(f2) + f1 * 0.001
    }

    return h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ cast(u64, f0 * 1000.0) ^ cast(u64, f1) ^ cast(u64, f2 * 100.0)
}

#[Swag.Optimize(false), Swag.NoInline]
func churnReference(count: u64)->u64
{
    var h0      = 1'u64
    var h1      = 3'u64
    var h2      = 5'u64
    var h3      = 7'u64
    var h4      = 11'u64
    var h5      = 13'u64
    var f0: f64 = 0.25
    var f1: f64 = 2.5
    var f2: f64 = 8.0
    for i in count
    {
        h0 = mixBits(h0, i)
        h1 += h0 ^ h5
        f0 = halve(f0 + f2)
        h2 = mixBits(h2 ^ h1, h3)
        h3 += h2 * h4
        f1 += f0 * f2
        h4 ^= mixBits(h3, h0)
        h5 += h4 + cast(u64, f1)
        f2 = halve(f2) + f1 * 0.001
    }

    return h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ cast(u64, f0 * 1000.0) ^ cast(u64, f1) ^ cast(u64, f2 * 100.0)
}

#test
{
    Swag.assert(churn(0) == churnReference(0))
    Swag.assert(churn(1) == churnReference(1))
    Swag.assert(churn(7) == churnReference(7))
    Swag.assert(churn(100) == churnReference(100))
}
