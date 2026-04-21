#global fileprivate

struct CustomVisitTooManyNames
{
    values: [2] s32 = [10, 20]
}

impl CustomVisitTooManyNames
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code void)
    {
        #if ptr do
            #error("CustomVisitTooManyNames does not expose pointer iteration.")

        #if back do
            #error("CustomVisitTooManyNames does not expose reverse iteration.")

        for idx in 2
        {
            #macro
            {
                let #alias0 = #up me.values[#up idx]
                let #alias1 = @index
                #inject(#up stmt)
            }
        }
    }
}

#test
{
    var arr: [2] s32 = [1, 2]
    foreach v, i, j in arr {} // swc-expected-error {{sema_err_foreach_too_many_names}}
}

#test
{
    var values = CustomVisitTooManyNames{}
    foreach value, ordinal, extra in values {} // swc-expected-error {{sema_err_foreach_too_many_names}}
}
