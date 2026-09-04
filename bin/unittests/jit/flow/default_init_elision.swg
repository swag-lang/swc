#global private

// Runtime behavior of safe default initialization. The late lowering gate removes
// a default only when flow proves that no read, lifecycle, escape, or custom setter
// can observe it.

var g_defaultDropCount: s32

struct DefaultDrop
{
    value: s32
}

impl DefaultDrop
{
    mtd opDrop()
    {
        g_defaultDropCount += 1
    }
}

func makeDefaultDrop(v: s32)->DefaultDrop
{
    var result: retval
    result.value = v
    return result
}

struct DefaultOuter
{
    d: DefaultDrop
    x: s32
}

struct ObservesDefault
{
    marker: s32 = 41
    value:  s32
}

impl ObservesDefault
{
    mtd opSet(value: s32)
    {
        Swag.assert(.marker == 41)
        .value = value
    }
}

struct FullyInitializedBySet
{
    first:  s32
    second: s32
}

impl FullyInitializedBySet
{
    mtd opSet(value: s32)
    {
        .first  = value
        .second = value + 1
    }
}

struct DefaultInitProbe
{
    a: u64
    b: u64
    c: u64
    d: u64
    e: u64
    f: u64
    g: u64
    h: u64
}

#[Swag.NoInline]
func defaultInitLoweringProbe(seed: u64)->u64
{
    var value: DefaultInitProbe
    value.a = seed
    value.b = seed + 1
    value.c = seed + 2
    value.d = seed + 3
    value.e = seed + 4
    value.f = seed + 5
    value.g = seed + 6
    value.h = seed + 7
    return value.a + value.b + value.c + value.d + value.e + value.f + value.g + value.h
}

func fillDefaultValue(p: *s32)
{
    p[] = 42
}

func defaultPair()->{ x: s32, y: s32 }
{
    var result: retval
    result.x = 1
    result.y = 2
    return result
}

// Straight-line scalar init.
#test
{
    var x: s32
    x = 7
    Swag.assert(x == 7)
}

// A setter that reads a member before writing cannot receive raw storage.
#test
{
    var value: ObservesDefault
    value = 8
    Swag.assert(value.marker == 41 and value.value == 8)
}

// No #[Swag.FullInit] is required: the setter's resolved body proves that it
// constructs every member, so its first call can receive raw storage.
#test
{
    var value: FullyInitializedBySet
    value = 8
    Swag.assert(value.first == 8 and value.second == 9)
}

// All fields are written before a read, so the 64-byte default is dead before
// codegen and only the eight construction stores reach the backend.
#test
{
    Swag.assert(defaultInitLoweringProbe(3) == 52)
}

// Out parameter: the default stays observable through the pointer.
#test
{
    var x: s32
    fillDefaultValue(&x)
    Swag.assert(x == 42)
}

// Array fill loop: arrays retain their safe default until range coverage analysis
// can prove every element is written.
#test
{
    var arr: [8] s32
    for i in 8 do
        arr[i] = cast(s32) i
    var sum = 0's32
    for i in 8 do
        sum += arr[i]
    Swag.assert(sum == 28)
}

// Destructuring assignment initializes every element.
#test
{
    var a: s32
    var b: s32
    {a, b} = defaultPair()
    Swag.assert(a == 1 and b == 2)
}

// defer reading a variable initialized later.
#test
{
    var x: s32
    defer Swag.assert(x == 9)
    x = 9
}

// The default value exists before the first replacement, so that replacement and
// the scope exit each drop one fully valid value.
#test
{
    g_defaultDropCount = 0
    {
        var v: DefaultDrop
        v = makeDefaultDrop(5)
        Swag.assert(v.value == 5)
    }
    Swag.assert(g_defaultDropCount == 2)
}

// Same at field granularity.
#test
{
    g_defaultDropCount = 0
    {
        var o: DefaultOuter
        o.d = makeDefaultDrop(3)
        o.x = 4
        Swag.assert(o.d.value == 3 and o.x == 4)
    }
    Swag.assert(g_defaultDropCount == 2)
}

// Each replacement drops the previous valid value, then scope exit drops the last.
#test
{
    g_defaultDropCount = 0
    {
        var v: DefaultDrop
        v = makeDefaultDrop(1)
        v = makeDefaultDrop(2)
        Swag.assert(v.value == 2)
    }
    Swag.assert(g_defaultDropCount == 3)
}
