#global fileprivate

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
    if var x = 0
    {
    }
    else
    {
        var y = x
    }
}

#test
{
    if var x = 1 where false
    {
    }
    else
    {
        var y = x
    }
}

#test
{
    if var x = 0 where x == 0
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

#test
{
    var result = 0
    var base = 42
    if var x: #null *s32 = &base where x != null
    {
        result = 1
    }
    else
    {
        result = -1
    }
    @assert(result == 1)
}

#test
{
    var result = 0
    if var x: #null string = null where x == null
    {
        result = 1
    }
    else
    {
        result = -1
    }
    @assert(result == 1)
}

#test
{
    var result = 0
    if var x: #null [..] s32 = null where x == null
    {
        result = 1
    }
    else
    {
        result = -1
    }
    @assert(result == 1)
}
