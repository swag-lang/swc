#global private

// Rewriting a left-hand `2.0 * x` inserts a copy before the two-address operation. The insertion
// can grow operand storage, so the multiply itself must already have become an addition.
#[Swag.NoInline, Swag.Optimize(true)]
func quadraticFlatEnough(p0x, p0y, p1x, p1y, p2x, p2y: f64, tolerance: f64)->bool
{
    let dx = p0x - 2.0 * p1x + p2x
    let dy = p0y - 2.0 * p1y + p2y
    return dx * dx + dy * dy <= tolerance * tolerance
}

#test
{
    @assert(quadraticFlatEnough(0, 0, 1, 3, 2, 6, 0.1))
}
