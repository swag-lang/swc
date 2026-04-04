#global fileprivate

#[Swag.Macro]
func macroPair(value: s32, stmt: #code void)
{
    let #alias0 = value
    let #alias1 = value + 1
    #inject(stmt)
}

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
    macroPair(|a, b, c| 10) // swc-expected-error {{sema_err_too_many_aliases}}
    {
    }
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
