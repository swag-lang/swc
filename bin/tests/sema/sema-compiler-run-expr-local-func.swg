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
