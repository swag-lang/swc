#global private

// Regression: a bare type name used as a value ('MyStruct') converts to 'typeinfo'
// in scalar initializations, but the same coercion was missing for the children of
// aggregate literals (struct and array). These tests execute the runtime side; the
// compile-time coverage lives in sema/casts/typeinfo_aggregate.swg.

struct MyStruct { x: s32 }
struct OtherStruct { y: f32 }

struct Holder
{
    t:   typeinfo
    tag: s32
}

const CReg: [?] Holder = [
    {MyStruct,    10},
    {OtherStruct, 20}]

#test
{
    // Scalar local initialization
    let t: typeinfo = MyStruct
    Swag.assert(t == MyStruct)
    Swag.assert(t == #typeof(MyStruct))
}

#test
{
    // Runtime struct literal, positional and named
    var h1: Holder = {MyStruct, 1}
    var h2: Holder = {t: OtherStruct, tag: 2}
    Swag.assert(h1.t == MyStruct)
    Swag.assert(h1.tag == 1)
    Swag.assert(h2.t == OtherStruct)
    Swag.assert(h2.tag == 2)
}

#test
{
    // Runtime array literal of typeinfo
    var arr: [2] typeinfo = [MyStruct, OtherStruct]
    Swag.assert(arr[0] == MyStruct)
    Swag.assert(arr[1] == OtherStruct)
    Swag.assert(arr[0] != arr[1])
}

#test
{
    // Runtime array of structs with a typeinfo field
    var reg: [2] Holder = [
        {MyStruct,    10},
        {OtherStruct, 20}]
    Swag.assert(reg[0].t == MyStruct)
    Swag.assert(reg[1].t == OtherStruct)
    Swag.assert(reg[0].tag == 10)
}

#test
{
    // A typeinfo variable mixed with real values in the same literal
    let t: typeinfo = MyStruct
    var h: Holder   = {t, 3}
    Swag.assert(h.t == MyStruct)
    Swag.assert(h.tag == 3)

    // The const registry is usable at runtime too
    Swag.assert(CReg[0].t == MyStruct)
    Swag.assert(CReg[0].t != CReg[1].t)
    Swag.assert(CReg[1].tag == 20)
}
