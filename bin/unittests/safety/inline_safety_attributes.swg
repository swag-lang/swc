#global private

#[Swag.Inline, Swag.Safety(.BoundCheck, true)]
func inlineSafetyBoundCheckEnabled()->bool
{
    return #safety(Swag.SafetyWhat.BoundCheck)
}

#[Swag.Inline, Swag.Safety(.BoundCheck, false)]
func inlineSafetyBoundCheckDisabled()->bool
{
    return #safety(Swag.SafetyWhat.BoundCheck)
}

#[Swag.Inline, Swag.Safety(.Overflow, true)]
func inlineSafetyOverflowEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Overflow)
}

#[Swag.Inline, Swag.CanOverflow(true)]
func inlineSafetyOverflowDisabledByCanOverflow()->bool
{
    return #safety(Swag.SafetyWhat.Overflow)
}

#[Swag.Inline, Swag.Safety(.Math, true)]
func inlineSafetyMathEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Math)
}

#[Swag.Inline, Swag.Safety(.Switch, true)]
func inlineSafetySwitchEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Switch)
}

#[Swag.Inline, Swag.Safety(.DynCast, true)]
func inlineSafetyDynCastEnabled()->bool
{
    return #safety(Swag.SafetyWhat.DynCast)
}

#[Swag.Inline, Swag.Safety(.Assume, true)]
func inlineSafetyAssumeEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Assume)
}

#[Swag.Inline, Swag.Safety(.Unreachable, true)]
func inlineSafetyUnreachableEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Unreachable)
}

#[Swag.Inline, Swag.Safety(.BoundCheck, true)]
func inlineSafetyArrayBoundCheck(idx: u64)->s32
{
    var values: [2] s32
    values[0] = 10
    values[1] = 20
    return values[idx] // swc-expected-error {{safety_err_runtime}}
}

#[Swag.Inline, Swag.Safety(.Overflow, true)]
func inlineSafetyAddOverflow(a, b: s8)->s8
{
    return a + b // swc-expected-error {{safety_err_runtime}}
}

#[Swag.Inline, Swag.Safety(.Overflow, true)]
func inlineSafetyMulOverflowS8(a, b: s8)->s8
{
    return a * b // swc-expected-error {{safety_err_runtime}}
}

#[Swag.Inline, Swag.Safety(.Overflow, true)]
func inlineSafetyDivOverflowS8(a, b: s8)->s8
{
    return a / b // swc-expected-error {{safety_err_runtime}}
}

#[Swag.Inline, Swag.Safety(.Overflow, true)]
func inlineSafetyModOverflowS16(a, b: s16)->s16
{
    return a % b // swc-expected-error {{safety_err_runtime}}
}

// Launders a compile-time constant through a non-inline call so the static sanitizer
// cannot prove the operand values: these tests target the RUNTIME overflow guard
// inherited from the inline callee's safety attribute.
func opaqueS8(v: s8)->s8
{
    return v
}

func opaqueS16(v: s16)->s16
{
    return v
}

#[Swag.Inline, Swag.CanOverflow(true)]
func inlineSafetyWrapAdd(value, delta: u8)->u8
{
    return value + delta
}

#test
{
    const BoundCheckOn  = #run inlineSafetyBoundCheckEnabled()
    const BoundCheckOff = #run inlineSafetyBoundCheckDisabled()
    const OverflowOn    = #run inlineSafetyOverflowEnabled()
    const OverflowOff   = #run inlineSafetyOverflowDisabledByCanOverflow()
    const MathOn        = #run inlineSafetyMathEnabled()
    const SwitchOn      = #run inlineSafetySwitchEnabled()
    const DynCastOn     = #run inlineSafetyDynCastEnabled()
    const AssumeOn      = #run inlineSafetyAssumeEnabled()
    const UnreachableOn = #run inlineSafetyUnreachableEnabled()

    #assert(BoundCheckOn == true)
    #assert(BoundCheckOff == false)
    #assert(OverflowOn == true)
    #assert(OverflowOff == false)
    #assert(MathOn == true)
    #assert(SwitchOn == true)
    #assert(DynCastOn == true)
    #assert(AssumeOn == true)
    #assert(UnreachableOn == true)
}

#test
{
    const Value = #run inlineSafetyArrayBoundCheck(2)
    @assert(Value == 0)
}

#test
{
    const Value = #run inlineSafetyAddOverflow(127's8, 1's8)
    @assert(Value == 0)
}

#test
{
    const Value = #run inlineSafetyMulOverflowS8(127's8, 2's8)
    @assert(Value == 0)
}

#test
{
    const Value = #run inlineSafetyDivOverflowS8(opaqueS8(-128's8), opaqueS8(-1))
    @assert(Value == 0)
}

#test
{
    const Value = #run inlineSafetyModOverflowS16(opaqueS16(-32768's16), opaqueS16(-1))
    @assert(Value == 0)
}

#test
{
    const Value = #run inlineSafetyWrapAdd(255'u8, 1'u8)
    #assert(Value == 0'u8)
}
