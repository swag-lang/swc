#global internal
/*
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
    // A constant case value can only appear once in a value-switch
    switch 1
    {
        case 1:
            break
        case 1: // swc-expected-error {{sema_err_switch_case_duplicate}}
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
*/
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
/*
#test
{
    // Invalid switch expr type
    var a : [4] s32
    switch a // swc-expected-error {{sema_err_switch_invalid_type}}
    {
    }
}

#test
{
    // Invalid range type
    var b = "hello"
    switch b
    {
        case "a" to "z": // swc-expected-error {{sema_err_switch_range_invalid_type}}
            break
        default:
            break
    }
}
*/