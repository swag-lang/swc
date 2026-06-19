#global fileprivate

#[Swag.Mixin]
func badMixinHole(value: s32)
{
    const #alias0: s32 = value
    const #alias2: s32 = value + 2 // swc-expected-error {{sema_err_alias_hole}}
}

#[Swag.Macro]
func badMacroHole(stmt: #code void)
{
    let #alias1 = 1 // swc-expected-error {{sema_err_alias_hole}}
    #inject(stmt)
}

#test
{
    badMixinHole(10)
}

#test
{
    badMacroHole()
    {
    }
}
