#global fileprivate

func runtimeName()->string
{
    return "User.Flag"
}

#test { const A = #hastag(runtimeName()) } // swc-expected-error {{sema_err_expr_not_const}}

#test
{
    var value = 1
    const B = #gettag("User.Count", s32, value) // swc-expected-error {{sema_err_expr_not_const}}
}
