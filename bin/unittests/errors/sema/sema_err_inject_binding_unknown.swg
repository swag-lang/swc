#global private

#[Swag.Macro]
func injectUnknownBinding(stmt: #code(value))
{
    #inject(stmt, missing = 1)     // swc-expected-error {{sema_err_inject_binding_unknown}}
}

#test
{
    injectUnknownBinding()
    {
        @print(value)
    }
}
