#global private

// A 'return <aggregate literal>' builds its value straight in the caller's return slot
// instead of filling a local temporary and copying it over. Only types returned through
// the ABI's hidden pointer are affected, so every struct here is deliberately larger than
// the 8 bytes that still travel in a register.

struct Vec3
{
    x, y, z: f32
}

struct Vec4
{
    x, y, z, w: f32
}

struct Big
{
    a, b, c, d, e: s64
}

struct Nested
{
    head: Vec4
    tail: Vec3
    tag:  s32
}

impl Vec4
{
    #[Swag.NoInline]
    mtd const scaled(f: f32)->Vec4
    {
        return Vec4{me.x * f, me.y * f, me.z * f, me.w * f}
    }

    // Permutes the components. A result built field by field over storage that aliases
    // 'me' would read back a component it has already overwritten, so this is the shape
    // that detects an unsound in-place construction.
    #[Swag.NoInline]
    mtd const reversed()->Vec4
    {
        return Vec4{me.w, me.z, me.y, me.x}
    }

    #[Swag.NoInline]
    mtd(op: Swag.Operator) const opBinary(other: const &Vec4)->Vec4
        where op == .Add
    {
        #static switch op
        {
        case .Add:
            return Vec4{me.x + other.x, me.y + other.y, me.z + other.z, me.w + other.w}
        }
    }

    // An inlined body returns into the caller's '__inline_result' local instead of a return
    // slot, so it takes the other half of the optimization.
    #[Swag.Inline]
    mtd const inlinedScaled(f: f32)->Vec4
    {
        return Vec4{me.x * f, me.y * f, me.z * f, me.w * f}
    }

    #[Swag.Inline]
    mtd const inlinedReversed()->Vec4
    {
        return Vec4{me.w, me.z, me.y, me.x}
    }
}

#[Swag.Inline]
func inlinedMakeBig(seed: s64)->Big
{
    return Big{seed + 1, seed + 2, seed + 3, seed + 4, seed + 5}
}

#[Swag.Inline]
func inlinedPick(which: s32)->Vec4
{
    if which == 0 do
        return Vec4{1, 2, 3, 4}
    return Vec4{5, 6, 7, 8}
}

#[Swag.NoInline]
func makeVec3(seed: f32)->Vec3
{
    return Vec3{seed, seed + 1, seed + 2}
}

#[Swag.NoInline]
func makeVec4(seed: f32)->Vec4
{
    return Vec4{seed, seed + 1, seed + 2, seed + 3}
}

#[Swag.NoInline]
func makeBig(seed: s64)->Big
{
    return Big{seed + 1, seed + 2, seed + 3, seed + 4, seed + 5}
}

#[Swag.NoInline]
func makeNested(seed: f32)->Nested
{
    return Nested{makeVec4(seed), makeVec3(seed + 10), 77}
}

// Several returns in one function must each target the same slot.
#[Swag.NoInline]
func pickVec4(which: s32)->Vec4
{
    if which == 0 do
        return Vec4{1, 2, 3, 4}
    if which == 1 do
        return Vec4{10, 20, 30, 40}
    return Vec4{100, 200, 300, 400}
}

// The literal is written into the caller's slot before the deferred action runs; the
// deferred write to a local must not disturb the value already produced.
var DeferWitness: s64 = 0

#[Swag.NoInline]
func makeBigWithDefer(seed: s64)->Big
{
    var scratch = seed
    defer
    {
        scratch      = -1
        DeferWitness = scratch
    }

    return Big{scratch, scratch * 2, scratch * 3, scratch * 4, scratch * 5}
}

#[Swag.NoInline]
func sumVec4(v: Vec4)->f32
{
    return v.x + v.y + v.z + v.w
}

// A literal returned from inside a loop, so the slot is targeted on a back edge.
#[Swag.NoInline]
func firstAbove(limit: f32)->Vec4
{
    for i in 10
    {
        let f = cast(f32) i
        if f > limit do
            return Vec4{f, f * 2, f * 3, f * 4}
    }

    return Vec4{-1, -1, -1, -1}
}

#[Swag.NoInline]
func makeArray(seed: s32)->[4] s32
{
    return [seed, seed + 1, seed + 2, seed + 3]
}

// Two 'retval' locals name the very same storage: the call below therefore receives a
// return slot that aliases its own receiver.
#[Swag.NoInline]
func aliasedReceiver()->Vec4
{
    var first: retval = undefined
    first.x = 1
    first.y = 2
    first.z = 3
    first.w = 4

    var second: retval = first.reversed()
    return second
}

#test
{
    let v = makeVec3(1)
    @assert(v.x == 1)
    @assert(v.y == 2)
    @assert(v.z == 3)
}

#test
{
    let v = makeVec4(5)
    @assert(v.x == 5)
    @assert(v.y == 6)
    @assert(v.z == 7)
    @assert(v.w == 8)
}

#test
{
    let b = makeBig(20)
    @assert(b.a == 21)
    @assert(b.b == 22)
    @assert(b.c == 23)
    @assert(b.d == 24)
    @assert(b.e == 25)
}

#test
{
    let n = makeNested(1)
    @assert(n.head.x == 1)
    @assert(n.head.w == 4)
    @assert(n.tail.x == 11)
    @assert(n.tail.z == 13)
    @assert(n.tag == 77)
}

#test
{
    @assert(pickVec4(0).x == 1)
    @assert(pickVec4(0).w == 4)
    @assert(pickVec4(1).x == 10)
    @assert(pickVec4(1).w == 40)
    @assert(pickVec4(2).x == 100)
    @assert(pickVec4(2).w == 400)
}

#test
{
    let b = makeBigWithDefer(3)
    @assert(b.a == 3)
    @assert(b.b == 6)
    @assert(b.c == 9)
    @assert(b.d == 12)
    @assert(b.e == 15)
    @assert(DeferWitness == -1)
}

#test
{
    let v = firstAbove(6.5)
    @assert(v.x == 7)
    @assert(v.y == 14)
    @assert(v.z == 21)
    @assert(v.w == 28)
}

#test
{
    let a = makeArray(4)
    @assert(a[0] == 4)
    @assert(a[1] == 5)
    @assert(a[2] == 6)
    @assert(a[3] == 7)
}

// The returned literal reads through 'me' and through a borrowed reference argument.
#test
{
    let a = makeVec4(1)
    let b = a.scaled(3)
    @assert(b.x == 3)
    @assert(b.y == 6)
    @assert(b.z == 9)
    @assert(b.w == 12)

    let c = a + b
    @assert(c.x == 4)
    @assert(c.y == 8)
    @assert(c.z == 12)
    @assert(c.w == 16)

    // Both operands are the same object, so the receiver and the borrowed argument alias.
    let d = a + a
    @assert(d.x == 2)
    @assert(d.y == 4)
    @assert(d.z == 6)
    @assert(d.w == 8)
}

#test
{
    let r = makeVec4(1).reversed()
    @assert(r.x == 4)
    @assert(r.y == 3)
    @assert(r.z == 2)
    @assert(r.w == 1)
}

#test
{
    let r = aliasedReceiver()
    @assert(r.x == 4)
    @assert(r.y == 3)
    @assert(r.z == 2)
    @assert(r.w == 1)
}

// The literal must reach a by-value parameter unchanged when it is consumed directly.
#test
{
    @assert(sumVec4(makeVec4(1)) == 10)
    @assert(sumVec4(Vec4{1, 2, 3, 4}) == 10)
}

#test
{
    let a = makeVec4(1)
    let b = a.inlinedScaled(2)
    @assert(b.x == 2)
    @assert(b.y == 4)
    @assert(b.z == 6)
    @assert(b.w == 8)

    let r = a.inlinedReversed()
    @assert(r.x == 4)
    @assert(r.y == 3)
    @assert(r.z == 2)
    @assert(r.w == 1)

    // The result overwrites the receiver it was computed from.
    var c = makeVec4(1)
    c = c.inlinedReversed()
    @assert(c.x == 4)
    @assert(c.y == 3)
    @assert(c.z == 2)
    @assert(c.w == 1)
}

#test
{
    let b = inlinedMakeBig(50)
    @assert(b.a == 51)
    @assert(b.c == 53)
    @assert(b.e == 55)

    @assert(inlinedPick(0).x == 1)
    @assert(inlinedPick(0).w == 4)
    @assert(inlinedPick(1).x == 5)
    @assert(inlinedPick(1).w == 8)
}

// Repeated expansions in one scope must each target their own result local.
#test
{
    var total: f32 = 0
    for i in 4
    {
        let v = makeVec4(cast(f32) i).inlinedScaled(2)
        total += v.x + v.y + v.z + v.w
    }

    @assert(total == 96)
}

// An inlined result feeding another inlined expansion.
#test
{
    let v = makeVec4(1).inlinedScaled(3).inlinedReversed()
    @assert(v.x == 12)
    @assert(v.y == 9)
    @assert(v.z == 6)
    @assert(v.w == 3)
}

#test
{
    let v = #run makeVec4(2)
    @assert(v.x == 2)
    @assert(v.y == 3)
    @assert(v.z == 4)
    @assert(v.w == 5)

    let b = #run makeBig(100)
    @assert(b.a == 101)
    @assert(b.e == 105)
}
