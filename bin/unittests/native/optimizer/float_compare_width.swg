#global private

// Two f32 values compare as f32. Every relational operator, the three-way
// compare, selects and branches on NaNs, signed zeros, infinities, subnormals
// and the extremes must answer as the same comparison done on the values
// widened to f64.

#[Swag.Optimize(true), Swag.NoInline]
func less(a, b: f32)->bool => a < b
#[Swag.Optimize(true), Swag.NoInline]
func lessEqual(a, b: f32)->bool => a <= b
#[Swag.Optimize(true), Swag.NoInline]
func greater(a, b: f32)->bool => a > b
#[Swag.Optimize(true), Swag.NoInline]
func greaterEqual(a, b: f32)->bool => a >= b
#[Swag.Optimize(true), Swag.NoInline]
func equal(a, b: f32)->bool => a == b
#[Swag.Optimize(true), Swag.NoInline]
func notEqual(a, b: f32)->bool => a != b
#[Swag.Optimize(true), Swag.NoInline]
func order(a, b: f32)->s32 => a <=> b
#[Swag.Optimize(true), Swag.NoInline]
func maxOf(a, b: f32)->f32 => a > b ? a : b
#[Swag.Optimize(true), Swag.NoInline]
func clampOf(x, lo, hi: f32)->f32 => x < lo ? lo : (x > hi ? hi : x)
#[Swag.Optimize(true), Swag.NoInline]
func countBelow(p: const [*] f32, n: u64, limit: f32)->u32
{
    var count = 0'u32
    for i in n
    {
        if p[i] < limit do
            count += 1
    }
    return count
}

#[Swag.Optimize(false), Swag.NoInline]
func wideLess(a, b: f32)->bool => cast(f64) a < cast(f64) b
#[Swag.Optimize(false), Swag.NoInline]
func wideLessEqual(a, b: f32)->bool => cast(f64) a <= cast(f64) b
#[Swag.Optimize(false), Swag.NoInline]
func wideEqual(a, b: f32)->bool => cast(f64) a == cast(f64) b
#[Swag.Optimize(false), Swag.NoInline]
func wideOrder(a, b: f32)->s32 => cast(f64) a <=> cast(f64) b

#[Swag.Safety(.All, false)]
#test
{
    let nan      = cast #bit (f32) 0x7FC00000'u32
    let negZero  = cast #bit (f32) 0x80000000'u32
    let inf      = cast #bit (f32) 0x7F800000'u32
    let tiny     = cast #bit (f32) 0x00000001'u32
    let largest  = cast #bit (f32) 0x7F7FFFFF'u32
    let values: [12] f32 = [0.0, negZero, 1.0, -1.0, 0.5, nan, inf, -inf, tiny, -tiny, largest, -largest]

    for a in values
    {
        for b in values
        {
            Swag.assert(less(a, b) == wideLess(a, b))
            Swag.assert(lessEqual(a, b) == wideLessEqual(a, b))
            Swag.assert(greater(a, b) == wideLess(b, a))
            Swag.assert(greaterEqual(a, b) == wideLessEqual(b, a))
            Swag.assert(equal(a, b) == wideEqual(a, b))
            Swag.assert(notEqual(a, b) == not wideEqual(a, b))
            Swag.assert(order(a, b) == wideOrder(a, b))

            let bigger = maxOf(a, b)
            Swag.assert(cast #bit (u32) bigger == cast #bit (u32) (wideLess(b, a) ? a : b))
            let clamped = clampOf(a, -1.0, 1.0)
            Swag.assert(cast #bit (u32) clamped == cast #bit (u32) (wideLess(a, -1.0) ? -1.0'f32 : (wideLess(1.0, a) ? 1.0'f32 : a)))
        }
    }

    Swag.assert(countBelow(&values[0], 12, 0.5) == 7)
}
