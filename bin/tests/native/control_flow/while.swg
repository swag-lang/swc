#global fileprivate // swc-option suite-test

#test
{
    while s32 {} // swc-expected-error {{sema_err_not_value_expr}}
}

#test
{
    var i = 0
    while i < 3
    {
        var x = 0
        i += 1
    }

    var y = x // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    var count = 0
    while count < 4
    {
        var x = 0
        count += 1
    }

    @assert(count == 4)
}

#test
{
    var outer = 0
    while outer < 2
    {
        var inner = 0
        while inner < 3
        {
            var x = 0
            inner += 1
        }

        outer += 1
    }

    @assert(outer == 2)
}
