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
    for i in 3
    {
        var x = i
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
    for #bit i in 3 // swc-expected-error {{sema_err_modifier_unsupported}}
    {
    }
}

#test
{
    for 1.5 // swc-expected-error {{sema_err_invalid_countof_type}}
    {
    }
}

#test
{
    for -1 // swc-expected-error {{sema_err_count_negative}}
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

#test
{
    for #reverse 5
    {
        var x = 0
    }
}

#test
{
    for #reverse i in 5
    {
        var x = i
    }
}

#test
{
    for
    {
        break
    }
}

#test
{
    for
    {
        break
    }
}

#test
{
    for i in 1 to 5
    {
        var x = i
    }
}

#test
{
    for i in 1 until 5
    {
        var x = i
    }
}

#test
{
    for #reverse i in 1 to 5
    {
        var x = i
    }
}

#test
{
    for #reverse i in 1 until 5
    {
        var x = i
    }
}

#test
{
    for i in 10 where i > 3
    {
        var x = i
    }
}

#test
{
    for i in 0 to 10 where i % 2 == 0
    {
        var x = i
    }
}

#test
{
    for i in 0 until 10 where i > 5
    {
        var x = i
    }
}

#test
{
    for #reverse i in 10 where i < 5
    {
        var x = i
    }
}

#test
{
    for i in 3
    {
        for j in 3
        {
            var x = i
            var y = j
        }
    }
}

#test
{
    for i in 1
    {
        for j in 1
        {
            var x = j
        }
        var y = j // swc-expected-error {{sema_err_unknown_symbol}}
    }
}

#test
{
    for 10
    {
        var x = 0
        break
    }
}

#test
{
    for i in 10
    {
        var x = i
        continue
        var y = 0 // Unreachable code is allowed
    }
}

#test
{
    for 2
    {
        for 2
        {
            break
        }
        var x = 0
    }
}

#test
{
    var arr: [5]s32 = [1, 2, 3, 4, 5]
    for arr
    {
        var x = 0
    }
}

#test
{
    var arr: [3]s32 = [1, 2, 3]
    for i in arr
    {
        var x = i
    }
}

#test
{
    for 3
    {
    }
}

#test
{
    for i in 0 to 3
    {
    }
}

#test
{
    for 3 do
        var x = 0
}

#test
{
    for i in 3 do
        var x = i
}

#test
{
    for i in 1
    {
    }

    for i in 1
    {
    }
}

#test
{
    var i = 5
    for i in 3
    {
        var x = i // shadows outer i
    }
}

#test
{
    for i in 5 where i > 0
    {
        var x = i
    }
}

#test
{
    var str: string
    for it in @countof(str) {}
    var v: u32
    for it in v {}
    var v1: s32
    for it in v1 {} // swc-expected-error {{sema_err_invalid_countof_type}}
}
