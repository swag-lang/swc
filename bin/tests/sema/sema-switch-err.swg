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

#test
{
    // A switch without an expression is a condition-switch; each case expression must be bool-compatible
    var a : [4] s32
    switch
    {
        case a: // swc-expected-error {{sema_err_cannot_cast}}
            break
        default:
            break
    }
}

#test
{
    // Invalid switch expr type
    var a : [4] s32
    switch a // swc-expected-error {{sema_err_switch_invalid_type}}
    {
        default:
            break
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

#test
{
    var a = 2
    switch a
    {
    case 1 where true:
        break
    case 1: // swc-expected-error {{sema_err_switch_case_duplicate}}
        break
    }
}


#test
{
    switch 1
    {
        default:
            break
        default: // swc-expected-error {{sema_err_switch_multiple_default}}
            break
    }
}

#test
{
    // Only unconditional defaults participate in duplicate-default checks.
    // `default where true` is unconditional.
    switch 1
    {
        default where true:
            break
        default: // swc-expected-error {{sema_err_switch_multiple_default}}
            break
    }
}

#test
{
    // `default where false` is conditional, so it should not be considered a duplicate default.
    switch 1
    {
        default where false:
            break
        default:
            break
    }
}

#test
{
    // Two conditional defaults are allowed.
    switch 1
    {
        default where false:
            break
        default where 1 < 2:
            break
    }
}

#test
{
    #[Swag.Complete]
    switch 1
    {
        case 1:
            break
        default: // swc-expected-error {{sema_err_switch_complete_has_default}}
            break
    }
}

#test
{
    // A complete switch should only reject an unconditional default.
    #[Swag.Complete]
    switch 1
    {
        case 1:
            break
        default where false:
            break
    }
}