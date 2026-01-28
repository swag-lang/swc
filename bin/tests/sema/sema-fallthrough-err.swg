#global internal

#test
{
    // Valid: fallthrough as last statement, and there is a following case
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
    // Error: fallthrough outside of a switch case
    fallthrough // swc-expected-error {{sema_err_fallthrough_outside_switch_case}}
}

#test
{
    // Error: fallthrough must be the last statement in a case
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
    // Error: fallthrough cannot be used in the last case
    var v = 1
    switch v
    {
        case 1:
            break
        default:
            fallthrough // swc-expected-error {{sema_err_fallthrough_in_last_case}}
    }
}
