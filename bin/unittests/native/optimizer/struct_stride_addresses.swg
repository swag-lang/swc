#global private

// Walking a slice of structs whose size takes a multiply to scale by (56
// bytes here) multiplies the index on every trip; the optimizer carries the
// element address instead and steps it by the size. Sizes the address
// arithmetic computes (12 and 24 bytes) keep their indexed address. Every
// function is forced to the optimizing backend, and the results are compared
// with the same code built without optimization: empty slices, a step of two,
// a counter that walks down, and a counter also read for its own value.

struct Body
{
    x, y, z:    f64
    vx, vy, vz: f64
    mass:       f64
}

struct Triple
{
    a, b, c: u32
}

struct Pair24
{
    key:   u64
    value: u64
    tag:   u64
}

#[Swag.Optimize(true), Swag.NoInline]
func moveBodies(bodies: [..] Body, dt: f64)
{
    for &b in bodies
    {
        b.x += dt * b.vx
        b.y += dt * b.vy
        b.z += dt * b.vz
    }
}

#[Swag.Optimize(false), Swag.NoInline]
func moveBodiesRef(bodies: [..] Body, dt: f64)
{
    for &b in bodies
    {
        b.x += dt * b.vx
        b.y += dt * b.vy
        b.z += dt * b.vz
    }
}

#[Swag.Optimize(true), Swag.NoInline]
func sumTriples(items: const [..] Triple)->u64
{
    var acc: u64
    for t in items do
        acc += cast(u64) t.a * 3 + cast(u64) t.b * 5 + cast(u64) t.c
    return acc
}

#[Swag.Optimize(false), Swag.NoInline]
func sumTriplesRef(items: const [..] Triple)->u64
{
    var acc: u64
    for t in items do
        acc += cast(u64) t.a * 3 + cast(u64) t.b * 5 + cast(u64) t.c
    return acc
}

// Every other element, and the index itself mixed into the sum.
#[Swag.Optimize(true), Swag.NoInline]
func sumEveryOther(items: const [..] Pair24)->u64
{
    var acc: u64
    var i:   u64
    while i < items.count
    {
        acc += items[i].value * 7 + items[i].tag + i
        i   += 2
    }
    return acc
}

#[Swag.Optimize(false), Swag.NoInline]
func sumEveryOtherRef(items: const [..] Pair24)->u64
{
    var acc: u64
    var i:   u64
    while i < items.count
    {
        acc += items[i].value * 7 + items[i].tag + i
        i   += 2
    }
    return acc
}

#[Swag.Optimize(true), Swag.NoInline]
func sumDownwards(items: const [..] Pair24)->u64
{
    var acc: u64
    var i = items.count
    while i > 0
    {
        i   -= 1
        acc = acc * 31 + items[i].key
    }
    return acc
}

#[Swag.Optimize(false), Swag.NoInline]
func sumDownwardsRef(items: const [..] Pair24)->u64
{
    var acc: u64
    var i = items.count
    while i > 0
    {
        i   -= 1
        acc = acc * 31 + items[i].key
    }
    return acc
}

// An empty slice whose bounds the compiler cannot see.
#[Swag.NoInline]
func none()->u64 => 0

#test
{
    var bodies, want: [5] Body
    for i in 5
    {
        let f = cast(f64) i
        bodies[i] = {f, f * 2.0, -f, 0.5 * f, -0.25 * f, 1.0 + f, 3.0}
        want[i]   = bodies[i]
    }
    moveBodies(bodies, 0.01)
    moveBodiesRef(want, 0.01)
    for i in 5 do
        Swag.assert(bodies[i].x == want[i].x and bodies[i].y == want[i].y and bodies[i].z == want[i].z)
    moveBodies(bodies[0 until none()], 0.01)
    Swag.assert(bodies[0].x == want[0].x)
}

#test
{
    var triples: [9] Triple
    for i in 9 do
        triples[i] = {cast(u32) i * 11, cast(u32) i * 7 + 1, 100 - cast(u32) i}
    Swag.assert(sumTriples(triples) == sumTriplesRef(triples))
    Swag.assert(sumTriples(triples[3 until 5]) == sumTriplesRef(triples[3 until 5]))
    Swag.assert(sumTriples(triples[0 until none()]) == 0)

    var pairs: [7] Pair24
    for i in 7 do
        pairs[i] = {cast(u64) i * 13 + 2, cast(u64) i * 5, cast(u64) i ^ 3}
    Swag.assert(sumEveryOther(pairs) == sumEveryOtherRef(pairs))
    Swag.assert(sumEveryOther(pairs[1 until 4]) == sumEveryOtherRef(pairs[1 until 4]))
    Swag.assert(sumDownwards(pairs) == sumDownwardsRef(pairs))
    Swag.assert(sumDownwards(pairs[0 until none()]) == 0)
}
