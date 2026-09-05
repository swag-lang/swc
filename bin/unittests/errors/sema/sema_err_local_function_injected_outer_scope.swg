#global private

#[Swag.Macro]
func invoke(stmt: #code)
{
    func local()
    {
        #inject(stmt)
    }
    local()
}

func bad()->s32
{
    var total = 0
    invoke() #code
    {
        total += 1     // swc-expected-error {{sema_err_local_function_outer_scope_variable}}
    }
    return total
}
