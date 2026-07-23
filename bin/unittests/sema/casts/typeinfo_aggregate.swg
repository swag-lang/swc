#global private

// Regression: a bare type name used as a value ('MyStruct') converts to 'typeinfo'
// in scalar initializations, but the same coercion was missing for the children of
// aggregate literals (struct and array), which failed with "cannot cast from
// 'MyStruct' to 'typeinfo'". The aggregate paths must normalize a type expression
// into a TypeValue constant exactly like the scalar path does.
// The runtime counterpart of this coverage lives in jit/reflection/typeinfo_aggregate.swg.

struct MyStruct { x: s32 }
struct OtherStruct { y: f32 }

struct Holder
{
    t:   typeinfo
    tag: s32
}

// Scalar initializations (already worked, kept as a guard)
const CT1: typeinfo = MyStruct
var g_T1: typeinfo = MyStruct
#assert(CT1 == MyStruct)
#assert(CT1 == #typeof(MyStruct))

// Const struct literal, positional and named
const CH1: Holder = {MyStruct, 1}
const CH2: Holder = {t: OtherStruct, tag: 2}
#assert(CH1.t == MyStruct)
#assert(CH1.tag == 1)
#assert(CH2.t == OtherStruct)

// Const array literal of typeinfo
const CA1: [?] typeinfo = [MyStruct, OtherStruct]
#assert(@countof(CA1) == 2)
#assert(CA1[0] == MyStruct)
#assert(CA1[1] == OtherStruct)

// Const array of structs with a typeinfo field: the registry pattern
const CReg: [?] Holder = [
    {MyStruct, 10},
    {OtherStruct, 20}]
#assert(CReg[0].t == MyStruct)
#assert(CReg[1].t == OtherStruct)
#assert(CReg[1].tag == 20)
