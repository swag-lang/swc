#global private

var RuntimeValue = 1

func nonConstantSwitch()
{
    #static switch RuntimeValue     // swc-expected-error {{sema_err_expr_not_const}}
    {
    case 1:
        return
    }
}

func duplicateCase()
{
    #static switch 1
    {
    case 1:
        return
    case 1:     // swc-expected-error {{sema_err_static_switch_case_duplicate}}
        return
    }
}

func duplicateDefault()
{
    #static switch 1
    {
    default:
        return
    default:     // swc-expected-error {{sema_err_static_switch_multiple_default}}
        return
    }
}
