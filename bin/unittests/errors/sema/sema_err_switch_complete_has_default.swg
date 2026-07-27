#global private

#test
{
    switch #complete 1
    {
    case 1:
        break
    default:     // swc-expected-error {{sema_err_switch_complete_has_default}}
        break
    }
}

// '#static switch #complete' rejects 'default' for the same reason.
const StaticDefaultValue = FileLevelDefaultEnum.A

enum FileLevelDefaultEnum
{
    A,
    B,
}

#[Swag.Compiler]
func staticSwitchDefault()->s32
{
    #static switch #complete StaticDefaultValue
    {
    case FileLevelDefaultEnum.A:
        return 1
    case FileLevelDefaultEnum.B:
        return 2
    default:     // swc-expected-error {{sema_err_switch_complete_has_default}}
        return 3
    }
}
