#global fileprivate

#[Swag.Macro]
func badInject(expr: #code s32)
{
    let value = #inject(1) // swc-expected-error {{sema_err_inject_requires_code}}
}

const BadInject = #run
{
    badInject(0)
    return 0
}
