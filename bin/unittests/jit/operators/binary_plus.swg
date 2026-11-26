#global private

#test
{
    func addManyMixed(a0: s32)->f64
    {
        return cast(f64, a0)
    }

    const V = #run addManyMixed(1)
    #assert(#typeof(V) == f64)
    #assert(V == 1.0_f64)
}

#test
{
    func add(a: s32, b: s32)->s32 { return a + b }
    const V = #run add(39, 3)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func add(a: f64, b: f64)->f64 { return a + b }
    const V = #run add(1.5_f64, 2.25_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 3.75_f64)
}

#test
{
    func add(a: s64, b: s64)->s64 { return a + b }
    const V = #run add(10000000000_s64, 7_s64)
    #assert(#typeof(V) == s64)
    #assert(V == 10000000007_s64)
}

#test
{
    func add(a: f32, b: f32)->f32 { return a + b }
    const V = #run add(1.25_f32, 2.5_f32)
    #assert(#typeof(V) == f32)
    #assert(V == 3.75_f32)
}

#test
{
    func add(a: f64, b: f64)->f64 { return a + b }
    const V = #run add(40, 2.5_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.5_f64)
}

#test
{
    #[Swag.Optimize(false)]
    func addPromotedFloat(v: f32)->f64
    {
        return v + 1.25_f64
    }

    const V = #run addPromotedFloat(42.5_f32)
    #assert(#typeof(V) == f64)
    #assert(V == 43.75_f64)
}

#test
{
    #[Swag.Optimize(false)]
    func multiplyWithNarrowedLiteral(v: f32)->f32
    {
        return v * 1.4247691104677813
    }

    const V = #run multiplyWithNarrowedLiteral(2.0_f32)
    #assert(#typeof(V) == f32)
    #assert(V == 2.0_f32 * 1.4247691104677813_f32)
}

#test
{
    #[Swag.Optimize(false)]
    func promotedFloatSource(v: f32)->f32
    {
        return v * 0.5_f32
    }

    #[Swag.Optimize(false)]
    func multiplyPromotedCall(v: f32)->f64
    {
        return promotedFloatSource(v) * 1.4247691104677813_f64
    }

    const V = #run multiplyPromotedCall(2.5_f32)
    #assert(#typeof(V) == f64)
    #assert(V == 1.25_f64 * 1.4247691104677813_f64)
}

#test
{
    func addManyInts(
        a0: s32, _: s32, _: s32, _: s32,
        _: s32, _: s32, _: s32, _: s32,
        _: s32, _: s32, _: s32, a11: s32)->s32
    {
        return a0 + a11
    }

    const V = #run addManyInts(40, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 2)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func addChainInt(a: s32, b: s32, c: s32, d: s32, e: s32)->s32 { return a + b + c + d + e }
    const V = #run addChainInt(30, 5, 4, 2, 1)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    #[Swag.Optimize(false)]
    func addChainFloat(a: f64, b: f64, c: f64, d: f64)->f64 { return a + b + c + d }
    const V = #run addChainFloat(10.0_f64, 20.5_f64, 5.25_f64, 6.25_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0_f64)
}

#test
{
    #[Swag.Optimize(true)]
    func addChainFloat(a: f64, b: f64, c: f64, d: f64)->f64 { return a + b + c + d }
    const V = #run addChainFloat(10.0_f64, 20.5_f64, 5.25_f64, 6.25_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0_f64)
}

#test
{
    #[Swag.Optimize(true)]
    func addChainFloat(a: f64, b: f64, c: f64, d: f64)->f64 { return a + b + c + d }
    const V = #run addChainFloat(10.0_f64, 20.5_f64, 5.25_f64, 6.25_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0_f64)
}

#test
{
    #[Swag.Optimize(false)]
    func thirdFloatArg(_: f64, _: f64, c: f64, _: f64)->f64 { return c }
    const V = #run thirdFloatArg(10.0_f64, 20.5_f64, 5.25_f64, 6.25_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 5.25_f64)
}

#test
{
    #[Swag.Optimize("bad")]     // swc-expected-error {{sema_err_cannot_cast}}
    func addAttrBad(a: s32, b: s32)->s32 { return a + b }
}

#test
{
    func addManyMixed(
        a0: s32, a1: f32, a2: s64, a3: f64, a4: u32, a5: f32,
        a6: s32, a7: f64, a8: u16, a9: f32, a10: s8, a11: f64)->f64
    {
        return cast(f64, a0) + cast(f64, a1) + cast(f64, a2) + a3 + cast(f64, a4) + cast(f64, a5) +
               cast(f64, a6) + a7 + cast(f64, a8) + cast(f64, a9) + cast(f64, a10) + a11
    }

    const V = #run addManyMixed(1, 2.5_f32, 3_s64, 4.0_f64, 5_u32, 6.0_f32, 7, 8.0_f64, 2_u16, 1.0_f32, 2_s8, 0.5_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0_f64)
}

#test
{
    func addStrict(a: s32, b: s32)->s32 { return a + b }
    const V = #run addStrict(1, 2, 3)     // swc-expected-error {{sema_err_too_many_arguments}}
}
