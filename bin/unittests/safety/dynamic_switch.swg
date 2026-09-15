#global private

#[Swag.Safety(.Switch, true)]
func completeDynamicSwitch(value: any)->s32
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    switch #complete
    {
    case let number = cast #try (*s32) value:
        return number[]
    }
}

#test
{
    discard completeDynamicSwitch(false)
}
