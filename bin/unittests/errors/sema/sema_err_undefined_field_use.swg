#global private

struct UndefinedPair
{
    left: s32
    right: s32
}

func readUndefinedField()->s32
{
    var value: UndefinedPair = undefined
    value.left = 1
    return value.right     // swc-expected-error {{sema_err_undefined_field_use}}
}
