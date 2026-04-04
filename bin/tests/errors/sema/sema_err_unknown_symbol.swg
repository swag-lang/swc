#global fileprivate

#test
{
    if let x = 1
    {
        let y = x
    }
    else
    {
        let z = x
    }

    let w = x // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    if let x = 4 where x > 2
    {
        let y = x
    }
}

#test
{
    if let x = 1 where false
    {
    }
    else
    {
        let y = x
    }
}

#test
{
    if let x = 4 where x > 2 do
        let y = x
}
