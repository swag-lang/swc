#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// A struct of at most eight bytes passed by value arrives in one register. When
// its home is only read field by field, each field is taken from that register
// by a shift instead of a reload. Fields of every width, negative values, an
// escaping copy and a rewritten field must keep the source results.

struct Pair32
{
    x, y: s32
}

struct Mixed
{
    a: u8
    b: u8
    c: u16
    d: s32
}

#[Swag.Optimize(true), Swag.NoInline]
func distance(p, q: Pair32)->s32
{
    let dx = p.x - q.x
    let dy = p.y - q.y
    return (dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy)
}

#[Swag.Optimize(true), Swag.NoInline]
func mixedSum(m: Mixed)->s64 => cast(s64) m.a + cast(s64) m.b * 256 + cast(s64) m.c * 65536 + cast(s64) m.d

#[Swag.Optimize(true), Swag.NoInline]
func highIsBigger(p: Pair32)->bool => p.y > p.x

#[Swag.NoInline]
func readThrough(p: *Pair32)->s32 => p.x * 10 + p.y

#[Swag.Optimize(true), Swag.NoInline]
func escaped(p: Pair32)->s32
{
    var q = p
    return readThrough(&q) + q.y
}

#[Swag.Optimize(true), Swag.NoInline]
func rewritten(p: Pair32)->s32
{
    var q = p
    q.y += 5
    return q.x - q.y
}

#test
{
    Swag.assert(distance(Pair32{1, 2}, Pair32{3, -2}) == 6)
    Swag.assert(distance(Pair32{-7, 9}, Pair32{-7, 9}) == 0)
    Swag.assert(mixedSum(Mixed{1, 2, 3, -4}) == 1 + 512 + 196608 - 4)
    Swag.assert(mixedSum(Mixed{0xFF, 0xFF, 0xFFFF, 0x7FFFFFFF}) == 0xFF + 0xFF00 + 0xFFFF0000 + 0x7FFFFFFF)
    Swag.assert(highIsBigger(Pair32{1, 2}))
    Swag.assert(not highIsBigger(Pair32{-1, -5}))
    Swag.assert(escaped(Pair32{3, 4}) == 38)
    Swag.assert(rewritten(Pair32{10, 1}) == 4)
}
