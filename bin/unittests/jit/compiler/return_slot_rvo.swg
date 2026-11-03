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
    mtd(op: Swag.Operator) const opBinary(other: Vec4)->Vec4
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
        let f = cast(f32, i)
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

// Two locals of the return type are two variables: only the returned one is built in the
// return slot, by a call that reads the other one.
#[Swag.NoInline]
func aliasedReceiver()->Vec4
{
    var first: #returntype
    first.x = 1
    first.y = 2
    first.z = 3
    first.w = 4

    var second: #returntype = first.reversed()
    return second
}

#test
{
    let v = makeVec3(1)
    Swag.require(v.x == 1)
    Swag.require(v.y == 2)
    Swag.require(v.z == 3)
}

#test
{
    let v = makeVec4(5)
    Swag.require(v.x == 5)
    Swag.require(v.y == 6)
    Swag.require(v.z == 7)
    Swag.require(v.w == 8)
}

#test
{
    let b = makeBig(20)
    Swag.require(b.a == 21)
    Swag.require(b.b == 22)
    Swag.require(b.c == 23)
    Swag.require(b.d == 24)
    Swag.require(b.e == 25)
}

#test
{
    let n = makeNested(1)
    Swag.require(n.head.x == 1)
    Swag.require(n.head.w == 4)
    Swag.require(n.tail.x == 11)
    Swag.require(n.tail.z == 13)
    Swag.require(n.tag == 77)
}

#test
{
    Swag.require(pickVec4(0).x == 1)
    Swag.require(pickVec4(0).w == 4)
    Swag.require(pickVec4(1).x == 10)
    Swag.require(pickVec4(1).w == 40)
    Swag.require(pickVec4(2).x == 100)
    Swag.require(pickVec4(2).w == 400)
}

#test
{
    let b = makeBigWithDefer(3)
    Swag.require(b.a == 3)
    Swag.require(b.b == 6)
    Swag.require(b.c == 9)
    Swag.require(b.d == 12)
    Swag.require(b.e == 15)
    Swag.require(DeferWitness == -1)
}

#test
{
    let v = firstAbove(6.5)
    Swag.require(v.x == 7)
    Swag.require(v.y == 14)
    Swag.require(v.z == 21)
    Swag.require(v.w == 28)
}

#test
{
    let a = makeArray(4)
    Swag.require(a[0] == 4)
    Swag.require(a[1] == 5)
    Swag.require(a[2] == 6)
    Swag.require(a[3] == 7)
}

// The returned literal reads through 'me' and through a borrowed reference argument.
#test
{
    let a = makeVec4(1)
    let b = a.scaled(3)
    Swag.require(b.x == 3)
    Swag.require(b.y == 6)
    Swag.require(b.z == 9)
    Swag.require(b.w == 12)

    let c = a + b
    Swag.require(c.x == 4)
    Swag.require(c.y == 8)
    Swag.require(c.z == 12)
    Swag.require(c.w == 16)

    // Both operands are the same object, so the receiver and the borrowed argument alias.
    let d = a + a
    Swag.require(d.x == 2)
    Swag.require(d.y == 4)
    Swag.require(d.z == 6)
    Swag.require(d.w == 8)
}

#test
{
    let r = makeVec4(1).reversed()
    Swag.require(r.x == 4)
    Swag.require(r.y == 3)
    Swag.require(r.z == 2)
    Swag.require(r.w == 1)
}

#test
{
    let r = aliasedReceiver()
    Swag.require(r.x == 4)
    Swag.require(r.y == 3)
    Swag.require(r.z == 2)
    Swag.require(r.w == 1)
}

// The literal must reach a by-value parameter unchanged when it is consumed directly.
#test
{
    Swag.require(sumVec4(makeVec4(1)) == 10)
    Swag.require(sumVec4(Vec4{1, 2, 3, 4}) == 10)
}

#test
{
    let a = makeVec4(1)
    let b = a.inlinedScaled(2)
    Swag.require(b.x == 2)
    Swag.require(b.y == 4)
    Swag.require(b.z == 6)
    Swag.require(b.w == 8)

    let r = a.inlinedReversed()
    Swag.require(r.x == 4)
    Swag.require(r.y == 3)
    Swag.require(r.z == 2)
    Swag.require(r.w == 1)

    // The result overwrites the receiver it was computed from.
    var c = makeVec4(1)
    c = c.inlinedReversed()
    Swag.require(c.x == 4)
    Swag.require(c.y == 3)
    Swag.require(c.z == 2)
    Swag.require(c.w == 1)
}

#test
{
    let b = inlinedMakeBig(50)
    Swag.require(b.a == 51)
    Swag.require(b.c == 53)
    Swag.require(b.e == 55)

    Swag.require(inlinedPick(0).x == 1)
    Swag.require(inlinedPick(0).w == 4)
    Swag.require(inlinedPick(1).x == 5)
    Swag.require(inlinedPick(1).w == 8)
}

// Repeated expansions in one scope must each target their own result local.
#test
{
    var total: f32 = 0
    for i in 4
    {
        let v = makeVec4(cast(f32, i)).inlinedScaled(2)
        total += v.x + v.y + v.z + v.w
    }

    Swag.require(total == 96)
}

// An inlined result feeding another inlined expansion.
#test
{
    let v = makeVec4(1).inlinedScaled(3).inlinedReversed()
    Swag.require(v.x == 12)
    Swag.require(v.y == 9)
    Swag.require(v.z == 6)
    Swag.require(v.w == 3)
}

#test
{
    let v = #run makeVec4(2)
    Swag.require(v.x == 2)
    Swag.require(v.y == 3)
    Swag.require(v.z == 4)
    Swag.require(v.w == 5)

    let b = #run makeBig(100)
    Swag.require(b.a == 101)
    Swag.require(b.e == 105)
}
