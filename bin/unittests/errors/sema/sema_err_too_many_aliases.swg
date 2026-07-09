#global private

#[Swag.Macro]
func macroPair(value: s32, stmt: #code(first: s32, second: s32))
{
    #inject(stmt, first = value, second = value + 1)
}

#test
{
    macroPair(10) #code(a, b, c) // swc-expected-error {{sema_err_too_many_aliases}}
    {
    }
}
