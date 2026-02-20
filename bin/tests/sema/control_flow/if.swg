#global internal

#test
{
    if true
    {
    }

    if false
    {
    }
    else
    {
    }

    if false
    {
    }
    elif true
    {
    }
    else
    {
    }
}

#test
{
    if true
    {
        var x = 0
    }

    var y = x // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    if true
    {
        var x = 0
    }
    else
    {
        var x = 1
    }
}

#test
{
    if true
    {
        if true
        {
            var x = 0
        }
    }
}

#test
{
    var x = 0
    var x = 0 // swc-expected-error {{sema_err_already_defined}}
}
