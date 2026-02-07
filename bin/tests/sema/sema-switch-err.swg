#global internal

#test
{
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
    var a : [4] s32
    switch a // swc-expected-error {{sema_err_switch_invalid_type}}
    {
        default:
            break
    }
}

#test
{
    var b = "hello"
    switch b
    {
        case "a" to "z": // swc-expected-error {{sema_err_invalid_range_type}}
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
    #[Swag.Complete]
    switch 1
    {
        case 1:
            break
        default where false:
            break
    }
}
