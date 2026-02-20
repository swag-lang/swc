#global internal

enum CmpEnum: u16
{
    A = 10
    B = 20
}

#test
{
    func eqS32(a: s32, b: s32)->bool { return a == b }
    const V0 = #run eqS32(42, 42)
    const V1 = #run eqS32(42, 43)
    #assert(V0)
    #assert(!V1)
}

#test
{
    func neS64(a: s64, b: s64)->bool { return a != b }
    const V0 = #run neS64(5000000000's64, 5000000001's64)
    const V1 = #run neS64(5000000000's64, 5000000000's64)
    #assert(V0)
    #assert(!V1)
}

#test
{
    func ltS32(a: s32, b: s32)->bool { return a < b }
    const V0 = #run ltS32(-5, 12)
    const V1 = #run ltS32(12, -5)
    #assert(V0)
    #assert(!V1)
}

#test
{
    func leS32(a: s32, b: s32)->bool { return a <= b }
    const V0 = #run leS32(12, 12)
    const V1 = #run leS32(13, 12)
    #assert(V0)
    #assert(!V1)
}

#test
{
    func gtU64(a: u64, b: u64)->bool { return a > b }
    const V0 = #run gtU64(0xFFFF_FFFF_FFFF_FFFF'u64, 1'u64)
    const V1 = #run gtU64(1'u64, 0xFFFF_FFFF_FFFF_FFFF'u64)
    #assert(V0)
    #assert(!V1)
}

#test
{
    func geU64(a: u64, b: u64)->bool { return a >= b }
    const V0 = #run geU64(9'u64, 9'u64)
    const V1 = #run geU64(8'u64, 9'u64)
    #assert(V0)
    #assert(!V1)
}

#test
{
    func cmpInt3Way(a: s32, b: s32)->s32 { return a <=> b }
    const V0 = #run cmpInt3Way(1, 2)
    const V1 = #run cmpInt3Way(2, 1)
    const V2 = #run cmpInt3Way(7, 7)
    #assert(V0 == -1)
    #assert(V1 == 1)
    #assert(V2 == 0)
}

#test
{
    func cmpEnum(a: CmpEnum, b: CmpEnum)->bool { return a == b }
    const V0 = #run cmpEnum(CmpEnum.A, CmpEnum.A)
    const V1 = #run cmpEnum(CmpEnum.A, CmpEnum.B)
    #assert(V0)
    #assert(!V1)
}

#test
{
    func cmpPointer(a: *void, b: *void)->bool { return a != b }
    const V0 = #run cmpPointer(cast(*void) 0x1234'u64, cast(*void) 0x5678'u64)
    const V1 = #run cmpPointer(cast(*void) 0x1234'u64, cast(*void) 0x1234'u64)
    const V2 = #run cmpPointer(null, cast(*void) 0x1'u64)
    #assert(V0)
    #assert(!V1)
    #assert(V2)
}

#test
{
    func cmpMixedFloat(a: f32, b: f64)->bool { return a < b }
    const V0 = #run cmpMixedFloat(1.25'f32, 2.0'f64)
    const V1 = #run cmpMixedFloat(3.5'f32, 2.0'f64)
    #assert(V0)
    #assert(!V1)
}

#test
{
    #[Swag.PrintMicro("post-emit")]
    func cmpFloat3Way(a: f64, b: f64)->s32 { return a <=> b }
    const V0 = #run cmpFloat3Way(1.5'f64, 2.5'f64)
    const V1 = #run cmpFloat3Way(2.5'f64, 1.5'f64)
    const V2 = #run cmpFloat3Way(3.25'f64, 3.25'f64)
    #assert(V0 == -1)
    #assert(V1 == 1)
    #assert(V2 == 0)
}

#test
{
    func cmpBad(a: bool, b: s32)->bool { return a < b } // swc-expected-error {{sema_err_compare_operand_type}}
}

//#test
//{
//    func cmpAbiMix(
//        a0: s8, a1: u16, a2: rune, a3: bool,
//        a4: f32, a5: f64, a6: s64, a7: u64,
//        a8: *void, a9: CmpEnum)->bool
//    {
//        return cast(s32) a0 < cast(s32) a1 and
//               cast(s32) a2 >= 65 and
//               a3 == true and
//               a4 <= cast(f32) a5 and
//               a6 < cast(s64) a7 and
//               a8 != null and
//               a9 == CmpEnum.B
//    }
//
//    const V0 = #run cmpAbiMix(
//        -3's8, 10'u16, 'A', true,
//        2.5'f32, 3.0'f64, 20's64, 30'u64,
//        cast(*void) 0x1111'u64, CmpEnum.B)
//
//    const V1 = #run cmpAbiMix(
//        10's8, 10'u16, 'A', true,
//        2.5'f32, 3.0'f64, 20's64, 30'u64,
//        cast(*void) 0x1111'u64, CmpEnum.B)
//
//    #assert(V0)
//    #assert(!V1)
//}
