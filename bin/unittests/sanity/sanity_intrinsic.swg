#global private

// '#sanity(...)' mirrors '#safety(...)': it evaluates, at compile time, whether the
// given static check is active here â€” the build-config default combined with the
// 'Swag.Sanity' overrides in scope.

#[Swag.Sanity(.Lifecycle, false)]
func lifecycleSanityDisabled()->bool
{
    return #sanity(Swag.SafetyWhat.Lifecycle)
}

#[Swag.Sanity(.Lifecycle, true)]
func lifecycleSanityEnabled()->bool
{
    return #sanity(Swag.SafetyWhat.Lifecycle)
}

// The two flag families are independent: turning the RUNTIME safety off does not
// touch the static sanity, and vice versa.
#[Swag.Safety(.BoundCheck, false)]
func sanityUnaffectedBySafety()->bool
{
    return #sanity(Swag.SafetyWhat.BoundCheck)
}

#test
{
    @assert(lifecycleSanityDisabled() == false)
    @assert(lifecycleSanityEnabled() == true)
}

#test
{
    const cfg      = #run dref notnull @compiler.getBuildCfg()
    const expected = cfg.sanityGuards & Swag.SafetyWhat.Null ? true : false
    #assert(#sanity(Swag.SafetyWhat.Null) == expected)
    #assert(sanityUnaffectedBySafety() == (cfg.sanityGuards & Swag.SafetyWhat.BoundCheck ? true : false))
}
