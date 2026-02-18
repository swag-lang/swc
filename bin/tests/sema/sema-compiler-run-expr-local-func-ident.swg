#global internal

alias PassAlias = s32

#test
{
    func passS32(x: s32) => x
    const V = #run passS32(42)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func passS64(x: s64) => x
    const V = #run passS64(5000000000's64)
    #assert(#typeof(V) == s64)
    #assert(V == 5000000000's64)
}

#test
{
    func passU32(x: u32) => x
    const V = #run passU32(123456'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 123456'u32)
}

#test
{
    func passU64(x: u64) => x
    const V = #run passU64(5000000000'u64)
    #assert(#typeof(V) == u64)
    #assert(V == 5000000000'u64)
}

#test
{
    func passF32(x: f32) => x
    const V = #run passF32(1.25'f32)
    #assert(#typeof(V) == f32)
    #assert(V == 1.25'f32)
}

#test
{
    func passF64(x: f64) => x
    const V = #run passF64(1.5'f64)
    #assert(#typeof(V) == f64)
    #assert(V == 1.5'f64)
}

#test
{
    func passRune(x: rune) => x
    const V = #run passRune('Z')
    #assert(#typeof(V) == rune)
    #assert(V == 'Z')
}

#test
{
    func passBool(x: bool) => x
    const V = #run passBool(true)
    #assert(#typeof(V) == bool)
    #assert(V == true)
}

#test
{
    func passAlias(x: PassAlias) => x
    const V = #run passAlias(77)
    #assert(#typeof(V) == PassAlias)
    #assert(cast(s32) V == 77)
}

#test
{
    func pickFourth(a: s32, b: s32, c: s32, d: s32) => d
    const V = #run pickFourth(1, 2, 3, 44)
    #assert(V == 44)
}

#test
{
    func pickFifth(a: s32, b: s32, c: s32, d: s32, e: s32) => e
    const V = #run pickFifth(1, 2, 3, 4, 55)
    #assert(V == 55)
}

#test
{
    func passViaLocal(x: s32)->s32
    {
        var y = x
        return y
    }

    const V = #run passViaLocal(99)
    #assert(V == 99)
}

#test
{
    func passErr(x: s32) => x
    const V = #run passErr() // swc-expected-error {{sema_err_too_few_arguments}}
}

#test
{
    func passErr(x: s32) => x
    const V = #run passErr("bad") // swc-expected-error {{sema_err_cannot_cast}}
}
