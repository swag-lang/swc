#global internal

#test
{
    var v = 1
    switch v
    {
        case 1:
            fallthrough
        case 2:
            break
        default:
            break
    }
}

#test
{
    fallthrough // swc-expected-error {{sema_err_fallthrough_outside_switch_case}}
}

#test
{
    var v = 1
    switch v
    {
        case 1:
            fallthrough // swc-expected-error {{sema_err_fallthrough_not_last_stmt}}
            break
        default:
            break
    }
}

#test
{
    var v = 1
    switch v
    {
        case 1:
            break
        default:
            fallthrough // swc-expected-error {{sema_err_fallthrough_in_last_case}}
    }
}

#test
{
    var v = 0
    switch v
    {
        case 0:
            fallthrough
        case 1:
            fallthrough
        case 2:
            break
    }
}

#test
{
    var v = 0
    switch v
    {
        case 0:
            fallthrough // swc-expected-error {{sema_err_fallthrough_not_last_stmt}}
            var a = 1
        case 1:
            break
    }
}
