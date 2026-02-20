#global internal

#test
{
    var sum = 0
    for var i = 0; i < 3; i += 1
    {
        sum += i
    }
}

#test
{
    for var i = 0; i < 1; i += 1
    {
        var x = i
    }

    var y = i // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    for var i = 0; s32; i += 1 {} // swc-expected-error {{sema_err_not_value_expr}}
}
