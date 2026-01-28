#global internal

#test
{
    // A switch with an expression requires constant case values
    var v = 1
    switch v
    {
        case v: // swc-expected-error {{sema_err_switch_case_not_const}}
            break
        default:
            break
    }
}

#test
{
    // Range case bounds must also be constant
    var v = 2
    switch v
    {
        case 1 to v: // swc-expected-error {{sema_err_switch_case_not_const}}
            break
        default:
            break
    }
}

#test
{
    // A switch without an expression is a condition-switch; each case expression must be bool-compatible
    var a : [4] s32
    switch
    {
        case a: // swc-expected-error {{sema_err_switch_case_not_bool}}
            break
        default:
            break
    }
}
