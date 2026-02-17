#global internal

#[Swag.Strict]
alias LocalStrict = s32

#test
{
    func localConst()->s32 { return 42 }
    const V = #run localConst()
    #assert(V == 42)
}

#test
{
    func depA()->s32 { return 7 }
    func depB()->s32 { return depA() }
    const V = #run depB()
    #assert(V == 7)
}

#test
{
    func takesArg(v: s32)->s32 { return 1 }
    const V = #run takesArg() // swc-expected-error {{sema_err_too_few_arguments}}
}

#test
{
    func takesArg(v: s32)->s32 { return 1 }
    const V = #run takesArg("bad") // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    func retBool()->bool { return true }
    const V = #run retBool()
    #assert(#typeof(V) == bool)
    #assert(V == true)
}

#test
{
    func retS32()->s32 { return 123456's32 }
    const V = #run retS32()
    #assert(#typeof(V) == s32)
    #assert(V == 123456's32)
}

#test
{
    func retS64()->s64 { return 5000000000's64 }
    const V = #run retS64()
    #assert(#typeof(V) == s64)
    #assert(V == 5000000000's64)
}

#test
{
    func retU32()->u32 { return 123456'u32 }
    const V = #run retU32()
    #assert(#typeof(V) == u32)
    #assert(V == 123456'u32)
}

#test
{
    func retU64()->u64 { return 5000000000'u64 }
    const V = #run retU64()
    #assert(#typeof(V) == u64)
    #assert(V == 5000000000'u64)
}

#test
{
    func retF32()->f32 { return 1.25'f32 }
    const V = #run retF32()
    #assert(#typeof(V) == f32)
    #assert(V == 1.25'f32)
}

#test
{
    func retF64()->f64 { return 1.5'f64 }
    const V = #run retF64()
    #assert(#typeof(V) == f64)
    #assert(V == 1.5'f64)
}

#test
{
    func retRune()->rune { return 'Z' }
    const V = #run retRune()
    #assert(#typeof(V) == rune)
    #assert(V == 'Z')
}

#test
{
    func retAlias()->LocalStrict { return cast(LocalStrict) 77 }
    const V = #run retAlias()
    #assert(#typeof(V) == LocalStrict)
    #assert(cast(s32) V == 77)
}

#test
{
    func retS8()->s8 { return 12's8 }
    const V = #run retS8()
    #assert(#typeof(V) == s8)
    #assert(V == 12's8)
}

#test
{
    func retS16()->s16 { return 1234's16 }
    const V = #run retS16()
    #assert(#typeof(V) == s16)
    #assert(V == 1234's16)
}

#test
{
    func retU8()->u8 { return 12'u8 }
    const V = #run retU8()
    #assert(#typeof(V) == u8)
    #assert(V == 12'u8)
}

#test
{
    func retU16()->u16 { return 1234'u16 }
    const V = #run retU16()
    #assert(#typeof(V) == u16)
    #assert(V == 1234'u16)
}

#test
{
    func retString()->string { return "run-expr" }
    const V = #run retString()
    #assert(#typeof(V) == string)
    #assert(V == "run-expr")
}

enum LocalEnum: u16 { A = 513 }
struct LocalStruct
{
    x: s32
    y: bool
}

#test
{
    func retEnum()->LocalEnum { return LocalEnum.A }
    const V = #run retEnum()
    #assert(#typeof(V) == LocalEnum)
    #assert(cast(u16) V == 513'u16)
}

#test
{
    func retStruct()->LocalStruct { return {x: 27, y: true} }
    const V = #run retStruct()
    #assert(#typeof(V) == LocalStruct)
    #assert(V.x == 27)
    #assert(V.y == true)
}

#test
{
    func retArray()->[3] s32 { return [1, 2, 3] }
    const V = #run retArray()
    #assert(V[0] == 1)
    #assert(V[1] == 2)
    #assert(V[2] == 3)
}

struct BigCopy
{
    a0: u64
    a1: u64
    a2: u64
    a3: u64
    a4: u64
    a5: u64
    a6: u64
    a7: u64
    a8: u64
}

#[Swag.Optimize(Swag.Optimization.O0)]
#test
{
    func makeBigCopy()->BigCopy
    {
        return {
            a0: 0x0102_0304_0506_0708'u64,
            a1: 0x1112_1314_1516_1718'u64,
            a2: 0x2122_2324_2526_2728'u64,
            a3: 0x3132_3334_3536_3738'u64,
            a4: 0x4142_4344_4546_4748'u64,
            a5: 0x5152_5354_5556_5758'u64,
            a6: 0x6162_6364_6566_6768'u64,
            a7: 0x7172_7374_7576_7778'u64,
            a8: 0x8182_8384_8586_8788'u64,
        }
    }

    const V = #run makeBigCopy()
    #assert(V.a0 == 0x0102_0304_0506_0708'u64)
    #assert(V.a1 == 0x1112_1314_1516_1718'u64)
    #assert(V.a2 == 0x2122_2324_2526_2728'u64)
    #assert(V.a3 == 0x3132_3334_3536_3738'u64)
    #assert(V.a4 == 0x4142_4344_4546_4748'u64)
    #assert(V.a5 == 0x5152_5354_5556_5758'u64)
    #assert(V.a6 == 0x6162_6364_6566_6768'u64)
    #assert(V.a7 == 0x7172_7374_7576_7778'u64)
    #assert(V.a8 == 0x8182_8384_8586_8788'u64)
}

#[Swag.Optimize(Swag.Optimization.O2)]
#test
{
    func makeBigCopy()->BigCopy
    {
        return {
            a0: 0x0102_0304_0506_0708'u64,
            a1: 0x1112_1314_1516_1718'u64,
            a2: 0x2122_2324_2526_2728'u64,
            a3: 0x3132_3334_3536_3738'u64,
            a4: 0x4142_4344_4546_4748'u64,
            a5: 0x5152_5354_5556_5758'u64,
            a6: 0x6162_6364_6566_6768'u64,
            a7: 0x7172_7374_7576_7778'u64,
            a8: 0x8182_8384_8586_8788'u64,
        }
    }

    const V = #run makeBigCopy()
    #assert(V.a0 == 0x0102_0304_0506_0708'u64)
    #assert(V.a1 == 0x1112_1314_1516_1718'u64)
    #assert(V.a2 == 0x2122_2324_2526_2728'u64)
    #assert(V.a3 == 0x3132_3334_3536_3738'u64)
    #assert(V.a4 == 0x4142_4344_4546_4748'u64)
    #assert(V.a5 == 0x5152_5354_5556_5758'u64)
    #assert(V.a6 == 0x6162_6364_6566_6768'u64)
    #assert(V.a7 == 0x7172_7374_7576_7778'u64)
    #assert(V.a8 == 0x8182_8384_8586_8788'u64)
}
