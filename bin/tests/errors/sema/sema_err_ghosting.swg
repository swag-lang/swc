#global fileprivate

func shadowed(value: s32)
{
    if true
    {
        var value = 1 // swc-expected-error {{sema_err_ghosting}}
    }
}
