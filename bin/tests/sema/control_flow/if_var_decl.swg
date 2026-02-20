#global internal

#test
{
    if var x = 1
    {
        var y = x
    }
    else
    {
        var z = x
    }

    var w = x // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    if var x: s32 = 1 where x
    {
        var y = x
    }
}

#test
{
    if var x: f32 = 1.0 // swc-expected-error {{sema_err_cannot_cast}}
    {
    }
}
