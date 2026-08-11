#global private

struct CustomVisitTooManyNames
{
    values: [2] s32 = [10, 20]
}

impl CustomVisitTooManyNames
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item: s32, index: u64))
        where !ptr
    {
        for idx in 2
        {
            #inject(stmt, item = me.values[idx], index = @index)
        }
    }
}

#test
{
    var arr: [2] s32 = [1, 2]
    for v, i, j in arr {}     // swc-expected-error {{sema_err_foreach_too_many_names}}
}

#test
{
    var values = CustomVisitTooManyNames{}
    for value, ordinal, extra in values {}     // swc-expected-error {{sema_err_too_many_aliases}}
}
