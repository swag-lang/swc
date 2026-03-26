#global fileprivate

#[Swag.Macro, Swag.CalleeReturn, Swag.Discardable]
func macroCaller(stmt: #code void)->s32
{
    #inject(stmt)
}

#[Swag.Mixin, Swag.CalleeReturn, Swag.Discardable]
func mixinCaller(stmt: #code void)->s32
{
    #inject(stmt)
}

func badMacroCaller()->bool
{
    macroCaller()
    {
        return 1 // swc-expected-error {{sema_err_cannot_cast}}
    }

    return false
}

func badMixinCaller()->bool
{
    mixinCaller()
    {
        return 1 // swc-expected-error {{sema_err_cannot_cast}}
    }

    return false
}
