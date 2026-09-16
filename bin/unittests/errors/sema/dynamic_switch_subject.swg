#global private

#test
{
    let value      = 42's32
    let boxed: any = value
    switch value
    {
    // swc-expected-error@(+1) {{sema_err_switch_binding_has_expr}}
    case let number = cast #try (*s32) boxed:
        break
    }
}
