#global private

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

// These helpers keep runtime safety tests from being reduced to static domain
// checks in release builds.
#[Swag.NoInline]
func opaqueF64(v: f64)->f64
{
    return v
}

#[Swag.NoInline]
func opaqueF32(v: f32)->f32
{
    return v
}

// Constant-domain failures are caught during semantic folding and retain the
// intrinsic argument as their primary location.
#[Swag.Safety(.Math, true)]
func invalidConstantSqrt()->f64
{
    return @sqrt(-1.0'f64)     // swc-expected-error {{safety_err_invalid_argument}}
}

#[Swag.Safety(.Math, true)]
func invalidConstantAsin()->f64
{
    return @asin(1.5'f64)     // swc-expected-error {{safety_err_invalid_argument}}
}

#[Swag.Safety(.Math, true)]
func invalidConstantLog()->f64
{
    return @log(0.0'f64)     // swc-expected-error {{safety_err_invalid_argument}}
}

#[Swag.Safety(.Math, true)]
func invalidConstantPow()->f64
{
    return @pow(-1.0'f64, 0.5'f64)     // swc-expected-error {{safety_err_invalid_argument}}
}

#test
{
    const cfg      = #run dref notnull @compiler.getBuildCfg()
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
        return @sqrt(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidSqrt(opaqueF64(-1.0))
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidAsin(v: f64)->f64
    {
        return @asin(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidAsin(opaqueF64(2.0))
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidAcos(v: f64)->f64
    {
        return @acos(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidAcos(opaqueF64(-2.0))
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidLog(v: f64)->f64
    {
        return @log(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidLog(opaqueF64(-1.0))
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidLog2(v: f64)->f64
    {
        return @log2(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidLog2(opaqueF64(-1.0))
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidLog10(v: f64)->f64
    {
        return @log10(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidLog10(opaqueF64(-1.0))
    @assert(value == 0.0)
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidPow(a, b: f64)->f64
    {
        return @pow(a, b)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidPow(opaqueF64(-1.0), opaqueF64(0.5))
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

    const value = #run invalidSqrtDisabled(opaqueF64(-1.0))
    @assert(value != value)
}

#test
{
    #[Swag.Safety(.Math, false)]
    func invalidLogDisabled(v: f64)->f64
    {
        return @log(v)
    }

    const value = #run invalidLogDisabled(opaqueF64(-1.0))
    @assert(value != value)
}

#test
{
    #[Swag.Safety(.Math, false)]
    func invalidPowDisabled(a, b: f64)->f64
    {
        return @pow(a, b)
    }

    const value = #run invalidPowDisabled(opaqueF64(-1.0), opaqueF64(0.5))
    @assert(value != value)
}

// =============================================
// f32 domain checks
// =============================================

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidSqrtF32(v: f32)->f32
    {
        return @sqrt(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidSqrtF32(opaqueF32(-1.0'f32))
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidAsinF32(v: f32)->f32
    {
        return @asin(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidAsinF32(opaqueF32(2.0'f32))
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidAcosF32(v: f32)->f32
    {
        return @acos(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidAcosF32(opaqueF32(-2.0'f32))
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidLogF32(v: f32)->f32
    {
        return @log(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidLogF32(opaqueF32(-1.0'f32))
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidLog2F32(v: f32)->f32
    {
        return @log2(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidLog2F32(opaqueF32(-1.0'f32))
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidLog10F32(v: f32)->f32
    {
        return @log10(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidLog10F32(opaqueF32(-1.0'f32))
}

#test
{
    #[Swag.Safety(.Math, true)]
    func invalidPowF32(a, b: f32)->f32
    {
        return @pow(a, b)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidPowF32(opaqueF32(-1.0'f32), opaqueF32(0.5'f32))
}

// =============================================
// Additional domain boundary cases
// =============================================

// @asin with value < -1
#test
{
    #[Swag.Safety(.Math, true)]
    func invalidAsinNeg(v: f64)->f64
    {
        return @asin(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidAsinNeg(opaqueF64(-2.0))
}

// @acos with value > 1
#test
{
    #[Swag.Safety(.Math, true)]
    func invalidAcosPos(v: f64)->f64
    {
        return @acos(v)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run invalidAcosPos(opaqueF64(2.0))
}

// Valid boundary: @asin(-1.0) and @acos(1.0) must not panic
#test
{
    #[Swag.Safety(.Math, true)]
    func validAsinBoundary()->f64
    {
        return @asin(-1.0'f64) + @asin(1.0'f64)
    }

    const value = #run validAsinBoundary()
}

#test
{
    #[Swag.Safety(.Math, true)]
    func validAcosBoundary()->f64
    {
        return @acos(-1.0'f64) + @acos(1.0'f64)
    }

    const value = #run validAcosBoundary()
}

// Valid: @sqrt(0.0) must not panic
#test
{
    #[Swag.Safety(.Math, true)]
    func validSqrtZero()->f64
    {
        return @sqrt(0.0'f64)
    }

    const value = #run validSqrtZero()
    @assert(value == 0.0)
}

// Valid: @pow with integer exponent on negative base must not panic
#test
{
    #[Swag.Safety(.Math, true)]
    func validPowIntExp(a, b: f64)->f64
    {
        return @pow(a, b)
    }

    const value = #run validPowIntExp(-2.0, 3.0)
    @assert(value == -8.0)
}
