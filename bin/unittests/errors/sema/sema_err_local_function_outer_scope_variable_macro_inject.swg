#global private

#[Swag.Macro]
func injectStmtInLocalFunction(stmt: #code)
{
    func runStmt()
    {
        #inject(stmt)
    }

    runStmt()
}

func bad(topLeft: s32)->s32
{
    var result = 0
    injectStmtInLocalFunction()
    {
        result = topLeft // swc-expected-error {{sema_err_local_function_outer_scope_variable}}
    }
    return result
}

const TriggerBad = #run bad(1)
