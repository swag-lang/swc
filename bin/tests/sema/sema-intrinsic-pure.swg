#global internal

func foldPureSqrt(x: f64)->f64 { return @sqrt(x) }
func foldPurePow(a: f64, b: f64)->f64 { return @pow(a, b) }
func foldPureMin(a: s32, b: s32)->s32 { return @min(a, b) }
func foldPureMix(a: f64, b: f64, c: f64)->f64 { return @muladd(@min(a, b), @max(b, c), @abs(c)) }

#test
{
    const typeSqrt = cast(const *Swag.TypeInfoFunc) #typeof(foldPureSqrt)
    const typePow = cast(const *Swag.TypeInfoFunc) #typeof(foldPurePow)
    const typeMin = cast(const *Swag.TypeInfoFunc) #typeof(foldPureMin)
    const typeMix = cast(const *Swag.TypeInfoFunc) #typeof(foldPureMix)
    #assert((typeSqrt.flags & .Pure) == 0)
    #assert((typePow.flags & .Pure) == 0)
    #assert((typeMin.flags & .Pure) == 0)
    #assert((typeMix.flags & .Pure) == 0)
}

#test
{
    const typeSqrt = cast(const *Swag.TypeInfoFunc) #typeof(foldPureSqrt)
    #assert((typeSqrt.flags & .Pure) != 0) // swc-expected-error {{sema_err_compiler_assert}}
}
