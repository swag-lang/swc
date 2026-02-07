#global internal

#test
{
    var v = 2
    switch v
    {
        case 1:
            break
        case 2, 3:
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
        default:
            break
    }

    switch 1
    {
        case 1:
            break
        default:
            break
    }
}

#test
{
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
        case .B:
            break
        case .C: // swc-expected-error {{sema_err_auto_scope_missing_enum_value}}
            break
        default:
            break
    }
}

#test
{
    enum E : s32
    {
        A = 1,
        B = 2,
        C = 3,
    }

    var v : E = .A
    #[Swag.Complete]
    switch v // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
        case .A:
            break
        case .B:
            break
    }
}

#test
{
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
        case A: // swc-expected-error {{sema_err_switch_case_duplicate}}
            break
        default:
            break
    }
}

#test
{
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
    var v = 2
    #[Swag.Complete]
    switch v
    {
        case 1 to 3:
            break
    }
}

func toto()->s32 => 1
#test
{
    #[Swag.Complete]
    switch toto()
    {
        case 1 to 3:
            break
    }
}

#test
{
    var a = 2
    var b = 1
    switch a
    {
    case 1 where b == 1:
        break
    case 1 where b == 2:
        break
    case 1:
        break
    }
}
