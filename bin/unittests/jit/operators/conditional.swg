#global private

enum CondEnum: u16
{
    A = 1
    B = 2
}

struct CondPair
{
    a: s32
    b: s32
}

#test
{
    func ternaryInt(cond: bool, a: s32, b: s32)->s32
    {
        return cond ? a : b
    }

    const V0 = #run ternaryInt(true, 42, 10)
    const V1 = #run ternaryInt(false, 42, 10)
    #assert(#typeof(V0) == s32)
    #assert(V0 == 42)
    #assert(V1 == 10)
}

#test
{
    func ternaryMixedNumeric(cond: bool)->f64
    {
        return cond ? 42 : 1.5'f64
    }

    const V0 = #run ternaryMixedNumeric(true)
    const V1 = #run ternaryMixedNumeric(false)
    #assert(#typeof(V0) == f64)
    #assert(V0 == 42.0'f64)
    #assert(V1 == 1.5'f64)
}

#test
{
    func ternaryFloat(cond: bool)->f64
    {
        return cond ? 42.5'f64 : 1.25'f64
    }

    const V0 = #run ternaryFloat(true)
    const V1 = #run ternaryFloat(false)
    #assert(#typeof(V0) == f64)
    #assert(V0 == 42.5'f64)
    #assert(V1 == 1.25'f64)
}

#test
{
    func ternaryString(cond: bool)->string
    {
        return cond ? "left" : "right"
    }

    const V0 = #run ternaryString(true)
    const V1 = #run ternaryString(false)
    #assert(#typeof(V0) == string)
    #assert(V0 == "left")
    #assert(V1 == "right")
}

#test
{
    func ternaryEnum(cond: bool)->CondEnum
    {
        return cond ? CondEnum.A : CondEnum.B
    }

    const V0 = #run ternaryEnum(true)
    const V1 = #run ternaryEnum(false)
    #assert(#typeof(V0) == CondEnum)
    #assert(V0 == CondEnum.A)
    #assert(V1 == CondEnum.B)
}

#test
{
    func ternaryPointer(cond: bool, p0: *void, p1: *void)->*void
    {
        return cond ? p0 : p1
    }

    const A = cast(*void) 0x1234'u64
    const B = cast(*void) 0x5678'u64
    const V0 = #run ternaryPointer(true, A, B)
    const V1 = #run ternaryPointer(false, A, B)
    #assert(V0 == A)
    #assert(V1 == B)
}

#test
{
    func ternaryCondInt(cond: s32)->s32
    {
        return cond ? 11 : 22
    }

    const V0 = #run ternaryCondInt(1)
    const V1 = #run ternaryCondInt(0)
    #assert(V0 == 11)
    #assert(V1 == 22)
}

#test
{
    func ternaryCondF32(cond: f32)->s32
    {
        return cond ? 7 : 9
    }

    const V0 = #run ternaryCondF32(1.5'f32)
    const V1 = #run ternaryCondF32(0.0'f32)
    #assert(V0 == 7)
    #assert(V1 == 9)
}

#test
{
    func ternaryCondPointer(cond: #null *void)->s32
    {
        return cond ? 7 : 9
    }

    const V0 = #run ternaryCondPointer(cast(*void) 0x1'u64)
    const V1 = #run ternaryCondPointer(cast(#null *void) 0'u64)
    #assert(V0 == 7)
    #assert(V1 == 9)
}

#test
{
    func ternaryBad(cond: bool)->s32
    {
        return cond ? 1 : "bad"     // swc-expected-error {{sema_err_binary_operand_type}}
    }
}

#test
{
    func ternaryNested(a: bool, b: bool)->s32
    {
        return a ? (b ? 42 : 7) : (b ? 9 : 10)
    }

    const V0 = #run ternaryNested(true, true)
    const V1 = #run ternaryNested(true, false)
    const V2 = #run ternaryNested(false, true)
    const V3 = #run ternaryNested(false, false)
    #assert(V0 == 42)
    #assert(V1 == 7)
    #assert(V2 == 9)
    #assert(V3 == 10)
}

#test
{
    func ternaryStruct(cond: bool)->CondPair
    {
        return cond ? {a: 1, b: 2} : {a: 3, b: 4}
    }

    const V0 = #run ternaryStruct(true)
    const V1 = #run ternaryStruct(false)
    #assert(V0.a == 1)
    #assert(V0.b == 2)
    #assert(V1.a == 3)
    #assert(V1.b == 4)
}

// A float selection consumed by an int conversion. The join register must be
// float-classed: an integer join used to bit-reinterpret the branches and to
// crash the x64 encoder on the conversion (int-int ConvertFloatToInt).
var g_CondTrue       = true
var g_Float15: f32   = 1.5
var g_Float25: f32   = 2.5
var g_Int42:   s32   = 42

#test
{
    let v = cast(s32) (g_CondTrue ? g_Float15 : g_Float25)
    @assert(v == 1)
    let w = cast(s32) (!g_CondTrue ? g_Float15 : g_Float25)
    @assert(w == 2)

    let f = g_CondTrue ? g_Float15 : g_Float25
    @assert(f == 1.5)
    @assert(f + g_Float25 == 4.0)
}

// A conditional wrapped by an implicit cast keeps its own result type; the
// wrapping cast converts the joined value. The s32 selection used to be
// bit-reinterpreted into the f32 binding instead of converted.
#test
{
    let x: f32 = g_CondTrue ? g_Int42 : 200
    @assert(x == 42.0)
    let y: f32 = !g_CondTrue ? g_Int42 : 200
    @assert(y == 200.0)
    let z: f64 = g_CondTrue ? g_Int42 : 200
    @assert(z == 42.0)
}

// Every consumer shape of a cast-wrapped integer selection: variable init with a
// pointer condition and a field branch, call argument, explicit cast, and return.
struct CondSt { col: s32 = 200 }

var g_CondSt: CondSt

#test
{
    func takeF(x: f32)->f32 { return x }
    func retF(c: bool, i: s32)->f32 { return c ? i : 200 }

    let p = &g_CondSt
    let f: f32 = p ? p.col : 200
    @assert(f == 200.0)

    @assert(takeF(g_CondTrue ? g_Int42 : 200) == 42.0)

    let a = cast(f32) (g_CondTrue ? g_Int42 : 200)
    @assert(a == 42.0)

    @assert(retF(true, 7) == 7.0)
    @assert(retF(false, 7) == 200.0)
}
