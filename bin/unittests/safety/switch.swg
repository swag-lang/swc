#global private

#[Swag.Safety(.Switch, false)]
func switchSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Switch)
}

#[Swag.Safety(.Switch, true)]
func switchSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Switch)
}

#test
{
    const cfg      = #run Swag.compiler().getBuildCfg()![]
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Switch ? true : false
    #assert(#safety(Swag.SafetyWhat.Switch) == expected)
}

#test
{
    const value = #run switchSafetyDisabled()
    #assert(value == false)
}

#test
{
    const value = #run switchSafetyEnabled()
    #assert(value == true)
}

#test
{
    #[Swag.Safety(.Switch, true)]
    func completeScalarSwitchPanic(v: s32)->s32
    {
        switch #complete v     // swc-expected-error {{safety_err_runtime}}
        {
        case 1 to 3:
            return 10
        }
    }

    const value = #run completeScalarSwitchPanic(9)
    Swag.require(value == 0)
}

#test
{
    #[Swag.Safety(.Switch, true)]
    func completeWhereSwitchPanic(v: s32)->s32
    {
        switch #complete v     // swc-expected-error {{safety_err_runtime}}
        {
        case 1 where false:
            return 10
        }
    }

    const value = #run completeWhereSwitchPanic(1)
    Swag.require(value == 0)
}

#test
{
    // Without its guard, a value no case matches walks past the switch: the code after it is
    // what this test observes, so the warning that it cannot run is silenced here.
    #[Swag.Safety(.Switch, false), Swag.Warning("sema_warn_unreachable_code", .Disable)]
    func completeScalarSwitchDisabled(v: s32)->s32
    {
        switch #complete v
        {
        case 1 to 3:
            return 10
        }

        return 77
    }

    const value = #run completeScalarSwitchDisabled(9)
    Swag.require(value == 77)
}

// Complete switch that actually matches must not panic
#test
{
    #[Swag.Safety(.Switch, true)]
    func completeScalarSwitchValid(v: s32)->s32
    {
        switch #complete v
        {
        case 1:
            return 10
        case 2 to 5:
            return 20
        case 6:
            return 30
        }
    }

    const value = #run completeScalarSwitchValid(3)
    Swag.require(value == 20)
}

// A default covers the remaining values even with switch safety enabled.
#test
{
    enum Color
    {
        Red
        Green
        Blue
    }

    #[Swag.Safety(.Switch, true)]
    func enumSwitchWithDefault(color: Color)->s32
    {
        switch color
        {
        case .Red:   return 1
        case .Green: return 2
        default:     break
        }

        return -1
    }

    Swag.require(enumSwitchWithDefault(Color.Blue) == -1)
    const value = #run enumSwitchWithDefault(Color.Blue)
    Swag.require(value == -1)
}

#test
{
    enum Color { Red, Green, Blue }

    func invalidColor()->Color
    {
        var color = Color.Red
        var bits  = 9's32
        Swag.memcpy(&color, &bits, #sizeof(Color))
        return color
    }

    #[Swag.Safety(.Switch, true)]
    func exhaustiveEnumSwitchPanic(color: Color)->bool
    {
        var matched = false
        switch color     // swc-expected-error {{safety_err_runtime}}
        {
        case .Red, .Green, .Blue: matched = true
        }

        return matched
    }

    const value = #run exhaustiveEnumSwitchPanic(invalidColor())
    Swag.require(not value)
}
