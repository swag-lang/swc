#global internal

#test
{
    // int-like switch
    var v = 2
    switch v
    {
        case 1:
        case 2, 3:
            break
        default:
            break
    }
}

#test
{
    // enum is valid if its underlying type is supported
    enum E : s32
    {
        A = 1,
        B = 2,
    }

    var v : E = E.B
    switch v
    {
        case E.A:
            break
        case A:
            break
        case .B:
            break
        case E.B:
            break
        case A, .C: // swc-expected-error {{sema_err_auto_scope_missing_enum_value}}
            break
        default:
            break
    }
}

#test
{
    // type alias is valid if its underlying type is supported
    alias MyInt = s32
    var v : MyInt = 3
    switch v
    {
        case 1:
            break
        case 3:
            break
        default:
            break
    }
}

#test
{
    // float switch
    var v = 1.5
    switch v
    {
        case 1.5:
            break
        default:
            break
    }
}

#test
{
    // bool switch
    var v = true
    switch v
    {
        case true:
            break
        default:
            break
    }
}

#test
{
    // string switch
    var v = "hello"
    switch v
    {
        case "hello", "world":
            break
        default:
            break
    }
}

#test
{
    // Range case only for numeric
    var v = 2
    switch v
    {
        case 1 to 3:
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
