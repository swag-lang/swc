#global private

func invalid(value: any)
{
    // swc-expected-error@(+1) {{sema_err_dynamic_cast_modifier}}
    let result = assume cast #bit(*s32, value)
}
