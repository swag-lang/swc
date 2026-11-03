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
    Holder{MyStruct, 10},
    Holder{OtherStruct, 20}]

#test
{
    // Scalar local initialization
    let t: typeinfo = MyStruct
    Swag.require(t == MyStruct)
    Swag.require(t == #typeof(MyStruct))
}

#test
{
    // Runtime struct literal, positional and named
    var h1: Holder = Holder{MyStruct, 1}
    var h2: Holder = Holder{t: OtherStruct, tag: 2}
    Swag.require(h1.t == MyStruct)
    Swag.require(h1.tag == 1)
    Swag.require(h2.t == OtherStruct)
    Swag.require(h2.tag == 2)
}

#test
{
    // Runtime array literal of typeinfo
    var arr: [2] typeinfo = [MyStruct, OtherStruct]
    Swag.require(arr[0] == MyStruct)
    Swag.require(arr[1] == OtherStruct)
    Swag.require(arr[0] != arr[1])
}

#test
{
    // Runtime array of structs with a typeinfo field
    var reg: [2] Holder = [
        Holder{MyStruct, 10},
        Holder{OtherStruct, 20}]
    Swag.require(reg[0].t == MyStruct)
    Swag.require(reg[1].t == OtherStruct)
    Swag.require(reg[0].tag == 10)
}

#test
{
    // A typeinfo variable mixed with real values in the same literal
    let t: typeinfo = MyStruct
    var h: Holder   = Holder{t, 3}
    Swag.require(h.t == MyStruct)
    Swag.require(h.tag == 3)

    // The const registry is usable at runtime too
    Swag.require(CReg[0].t == MyStruct)
    Swag.require(CReg[0].t != CReg[1].t)
    Swag.require(CReg[1].tag == 20)
}
