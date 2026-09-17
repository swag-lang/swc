#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// A struct of at most eight bytes built field by field and then passed or
// returned whole is assembled in a register. Fields of every width, negative
// values, fields left to their default and an aggregate whose address
// escapes must keep their bytes.

struct Pair
{
    a, b: u32
}

struct Mixed
{
    x: u8
    y: u8 = 0xAB
    z: u16
    w: s32
}

struct Quad
{
    p, q: s16
}

#[Swag.Optimize(true), Swag.NoInline]
func makePair(x, y: u32)->Pair => Pair{y, x}

#[Swag.NoInline]
func usePair(p: Pair)->u64 => cast(u64) p.a * 1000 + cast(u64) p.b

#[Swag.Optimize(true), Swag.NoInline]
func passPair(x, y: u32)->u64 => usePair(Pair{x, y + 1})

#[Swag.Optimize(true), Swag.NoInline]
func makeMixed(x: u8, w: s32)->Mixed
{
    var m: Mixed
    m.x = x
    m.z = 300
    m.w = w
    return m
}

#[Swag.Optimize(true), Swag.NoInline]
func makeQuad(p, q: s16)->Quad => Quad{p, q}

#[Swag.NoInline]
func touch(q: *Quad)
{
    q.p += 1
}

#[Swag.Optimize(true), Swag.NoInline]
func escaped(p, q: s16)->s32
{
    var v = Quad{p, q}
    touch(&v)
    let copy = v
    return cast(s32) copy.p * 100 + cast(s32) copy.q
}

#test
{
    let p = makePair(1, 0xFFFFFFFF)
    Swag.assert(p.a == 0xFFFFFFFF and p.b == 1)
    Swag.assert(passPair(7, 8) == 7009)

    let m = makeMixed(0xFE, -5)
    Swag.assert(m.x == 0xFE and m.y == 0xAB and m.z == 300 and m.w == -5)

    let q = makeQuad(-2, 3)
    Swag.assert(q.p == -2 and q.q == 3)
    Swag.assert(escaped(4, -6) == 494)
}
