#global private

func invalid(value: any)
{
    // swc-expected-error@(+1) {{sema_err_dynamic_cast_modifier}}
    let result = cast #try #assume (*s32) value
}
