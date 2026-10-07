#global private

// A store is dead when a later store to the same place overwrites it and nothing in between
// can read what it wrote; a reload into the register that already holds the stored value is
// no load at all. Both rest on one rule: two accesses through the same pointer are apart
// when their bytes are, and any other pointer may name the same place. Each function is
// called with distinct pointers and with aliased ones, and must agree with the source.

struct Pair
{
    a, b: s64
}

struct Reals
{
    x, y: f64
}

// The first write to 'a' is never read: the write to 'b' and its reload are other bytes.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func overwrite(p: *Pair, seed: s64)->s64
{
    p.a = seed
    p.b = seed * 3
    let kept = p.b
    p.a = kept + 1
    return p.a + p.b
}

// 'q' may be 'p': its read sees the first write, which therefore stays.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func overwriteAroundRead(p, q: *Pair, seed: s64)->s64
{
    p.a = seed
    let seen = q.a
    p.a = seed + 10
    return seen
}

// 'q' may be 'p': its write lands between the store and the reload of 'p.a'.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func reloadAroundWrite(p, q: *Pair, seed: s64)->s64
{
    p.a = seed
    q.a = seed + 5
    return p.a
}

// An accumulation through one pointer keeps its running value in a register; the writes to
// 'y' never touch 'x'.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func accumulate(r: *Reals, step: f64)->f64
{
    r.x += step
    r.y -= step
    r.x += step * 2
    r.y -= step * 2
    r.x += step * 4
    return r.x + r.y
}

// The same accumulation with a second pointer in the way, which may be the first.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func accumulateAround(r, other: *Reals, step: f64)->f64
{
    r.x     += step
    other.x *= 2
    r.x     += step * 2
    other.x *= 2
    r.x     += step * 4
    return r.x
}

// A narrow store does not cover a wider one that came first.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func narrowOverWide(p: *Pair, low: u32)->s64
{
    p.a = 0x1122334455667788
    let half = cast(*u32, &p.a)
    half[] = low
    return p.a
}

#test
{
    var first, second: Pair
    let overwritten = overwrite(&first, 7)
    Swag.assert(overwritten == 43 and first.a == 22 and first.b == 21)

    first.a  = 100
    second.a = 200
    let apart = overwriteAroundRead(&first, &second, 5)
    Swag.assert(apart == 200 and first.a == 15)
    let together = overwriteAroundRead(&first, &first, 5)
    Swag.assert(together == 5 and first.a == 15)

    let reloadedApart = reloadAroundWrite(&first, &second, 30)
    Swag.assert(reloadedApart == 30 and second.a == 35)
    let reloadedTogether = reloadAroundWrite(&first, &first, 30)
    Swag.assert(reloadedTogether == 35 and first.a == 35)

    var reals: Reals = {1.0, 10.0}
    let summed       = accumulate(&reals, 0.5)
    Swag.assert(summed == 13.0 and reals.x == 4.5 and reals.y == 8.5)

    var left:  Reals = {1.0, 0.0}
    var right: Reals = {3.0, 0.0}
    let kept         = accumulateAround(&left, &right, 0.5)
    Swag.assert(kept == 4.5 and right.x == 12.0)
    left.x = 1.0
    let mixed = accumulateAround(&left, &left, 0.5)
    Swag.assert(mixed == 10.0 and left.x == 10.0)

    let narrowed = narrowOverWide(&first, 0xAABBCCDD)
    Swag.assert(narrowed == 0x11223344AABBCCDD)
}
