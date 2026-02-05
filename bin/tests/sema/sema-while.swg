#global internal

#test
{
    while s32 {} // swc-expected-error {{sema_err_not_value_expr}}
}

#test
{
    while true
    {
        var x = 0
    }

    var y = x // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    while true
    {
        var x = 0
    }
}

#test
{
    while true
    {
        while true
        {
            var x = 0
        }
    }
}
