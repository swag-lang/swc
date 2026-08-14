#global private

// A struct of one, two, four, or eight bytes is passed by value in a register, the way the
// native ABI passes the integer of that width, and the callee spills it to a local home
// before reading it. These tests drive that path through every call shape that reaches the
// callee: direct, function pointer, stack slot, forwarding, mixed float lanes, and lifecycle.
// Arrays are deliberately absent: an array parameter is a view of the caller's storage and
// stays indirect whatever its size (see 'exact_array_param.swg').

struct Only1
{
    a: u8
}

struct Only2
{
    a: u8
    b: u8
}

struct Only4
{
    a: u16
    b: u16
}

struct Pair
{
    x: u32
    y: u32
}

struct FloatPair
{
    x: f32
    y: f32
}

var GSeed: u64 = 7

func sum1(v: Only1)->u32             => cast(u32) v.a
func sum2(v: Only2)->u32             => cast(u32) v.a * 100 + cast(u32) v.b
func sum4(v: Only4)->u32             => cast(u32) v.a * 1000 + cast(u32) v.b
func sumPair(v: Pair)->u32           => v.x * 1000 + v.y
func sumFloatPair(v: FloatPair)->f32 => v.x + v.y

// The fifth argument lands in a stack slot rather than a register.
func sumPairStack(a, b, c, d: u64, v: Pair)->u64 => a + b + c + d + cast(u64) v.x * 3 + cast(u64) v.y

// The integer lane between two float lanes carries the aggregate.
func sumMixedLanes(a: f64, v: Pair, b: f64)->f64 => a + cast(f64) (v.x + v.y) + b

// The parameter has a memory home: its address is a real address.
func sumViaAddress(v: Pair)->u32
{
    let p = &v
    return p.x + p.y
}

// Forwarding reloads the register image out of the parameter's home.
func sumForwarded(v: Pair)->u32 => sumPair(v)

#test
{
    @assert(sum1({42}) == 42)
    @assert(sum2({4, 2}) == 402)
    @assert(sum4({4, 2}) == 4002)
    @assert(sumPair({18, 24}) == 18024)
    @assert(sumFloatPair({1.5, 2.25}) == 3.75)
}

#test
{
    var v: Pair
    v.x = 30
    v.y = 12
    @assert(sumPair(v) == 30012)
    @assert(sumViaAddress(v) == 42)
    @assert(sumForwarded(v) == 30012)
}

#test
{
    @assert(sumPairStack(1, 2, 3, 4, {10, 20}) == 60)
    @assert(sumMixedLanes(1.5, {20, 21}, 0.75) == 43.25)
}

// The exact shape a native drop-target vtable calls back with, both sides Swag here.
struct DragVTable
{
    onDrag: func(u32, Pair, *u32)->u32
}

#test
{
    var vtbl: DragVTable = undefined
    vtbl.onDrag = func(state: u32, pt: Pair, effect: *u32)->u32
    {
        effect[] = pt.x + pt.y
        return state + pt.x * 1000 + pt.y
    }

    var effect: u32
    @assert(vtbl.onDrag(5, {30, 12}, &effect) == 30017)
    @assert(effect == 42)
}

#test
{
    let base = 5'u32
    let cb: func||(Pair)->u32 = func|base|(v: Pair)->u32
    {
        return base + v.x + v.y
    }

    @assert(cb({1, 2}) == 8)
}

var GDropCount: s32

// Eight bytes with a drop hook: the register image is a transport copy, so the callee runs
// no lifecycle on it and ownership stays with the caller.
struct Owned
{
    token: u64
}

impl Owned
{
    mtd opDrop()
    {
        GDropCount += 1
    }
}

func readToken(v: Owned)->u64 => v.token

func dropProbe()->s32
{
    var o: Owned
    o.token = GSeed
    @assert(readToken(o) == GSeed)
    return GDropCount
}

#test
{
    GDropCount = 0
    @assert(dropProbe() == 0)
    @assert(GDropCount == 1)
}
