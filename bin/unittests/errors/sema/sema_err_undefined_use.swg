#global private

func readUndefined()->s32
{
    var value: s32 = undefined
    return value     // swc-expected-error {{sema_err_undefined_use}}
}
