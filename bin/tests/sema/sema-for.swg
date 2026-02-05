#global internal

#test
{
    for 3
    {
        var x = 0
    }
}

#test
{
    for #reverse i in 3
    {
        var x = i
    }

    var y = i // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    for 1.5 // swc-expected-error {{sema_err_invalid_countof_type}}
    {
    }
}

#test
{
    for i in 0.0 to 1.5 // swc-expected-error {{sema_err_invalid_countof_type}}
    {
        var x = i
    }
}

#test
{
    for i in 3 where s32 // swc-expected-error {{sema_err_not_value_expr}}
    {
        var x = i
    }
}
