#global private

// A scope is opened by 'scope'. A '{' that starts a statement opens nothing by itself.
#test
{
    var total = 0
    scope
    {
        let inner = 1
        total += inner
    }

    {     // swc-expected-error {{parser_err_bare_scope}}
        total += 1
    }

    Swag.assert(total == 2)
}

#test
{
    let value = 1
    if value == 1
    {
        { discard value }     // swc-expected-error {{parser_err_bare_scope}}
    }
}
