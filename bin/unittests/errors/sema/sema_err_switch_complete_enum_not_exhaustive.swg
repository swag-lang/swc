#global private

enum FileLevelAttrEnum
{
    A,
    B
}

#test
{
    var v = FileLevelAttrEnum.A
    switch #complete v     // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
    case FileLevelAttrEnum.A:
        break
    // case FileLevelAttrEnum.B:
    //    break
    }
}

// '#static switch #complete' requires the same coverage.
const StaticEnumValue = FileLevelAttrEnum.A

#[Swag.Compiler]
func staticSwitchNotExhaustive()->s32
{
    #static switch #complete StaticEnumValue     // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
    case FileLevelAttrEnum.A:
        return 1
    }
}
