#global fileprivate

#[Swag.Safety(.Math, false)]
func mathSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Math)
}

#[Swag.Safety(.Math, true)]
func mathSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Math)
}

#test
{
    const cfg      = #run dref @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Math ? true : false
    #assert(#safety(Swag.SafetyWhat.Math) == expected)
}

#test
{
    const value = #run mathSafetyDisabled()
    #assert(value == false)
}

#test
{
    const value = #run mathSafetyEnabled()
    #assert(value == true)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidSqrt(v: f64)->f64
    {
        return @sqrt(v) // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidSqrt(-1.0)
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidAsin(v: f64)->f64
    {
        return @asin(v) // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidAsin(2.0)
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidAcos(v: f64)->f64
    {
        return @acos(v) // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidAcos(-2.0)
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidLog(v: f64)->f64
    {
        return @log(v) // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidLog(-1.0)
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidLog2(v: f64)->f64
    {
        return @log2(v) // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidLog2(-1.0)
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidLog10(v: f64)->f64
    {
        return @log10(v) // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidLog10(-1.0)
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidPow(a, b: f64)->f64
    {
        return @pow(a, b) // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidPow(-1.0, 0.5)
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func validMath(a, b: f64)->f64
    {
        return @sqrt(a) + @log(b) + @asin(0.0'f64) + @acos(1.0'f64) + @pow(2.0'f64, 3.0'f64)
    }

    const value = #run validMath(9.0, 1.0)
    @assert(value == 11.0)
}

#test
{
    #[Swag.Safety(.Math, false)]
    func invalidSqrtDisabled(v: f64)->f64
    {
        return @sqrt(v)
    }

    const value = #run invalidSqrtDisabled(-1.0)
    @assert(value != value)
}

#test
{
    #[Swag.Safety(.Math, false)]
    func invalidLogDisabled(v: f64)->f64
    {
        return @log(v)
    }

    const value = #run invalidLogDisabled(-1.0)
    @assert(value != value)
}

#test
{
    #[Swag.Safety(.Math, false)]
    func invalidPowDisabled(a, b: f64)->f64
    {
        return @pow(a, b)
    }

    const value = #run invalidPowDisabled(-1.0, 0.5)
    @assert(value != value)
}
