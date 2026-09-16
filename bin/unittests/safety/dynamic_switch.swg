#global private

#[Swag.Safety(.Switch, true)]
func completeDynamicSwitch(value: any)->s32
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    switch #complete value
    {
    case s32 as number:
        return number[]
    }
}

#test
{
    discard completeDynamicSwitch(false)
}
