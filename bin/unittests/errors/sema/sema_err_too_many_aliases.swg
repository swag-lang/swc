#global fileprivate

#[Swag.Macro]
func macroPair(value: s32, stmt: #code void)
{
    let #alias0 = value
    let #alias1 = value + 1
    #inject(stmt)
}

#test
{
    macroPair(|a, b, c| 10) // swc-expected-error {{sema_err_too_many_aliases}}
    {
    }
}
