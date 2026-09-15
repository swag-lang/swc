#global private

func(T) requiresText(value: T)->T where T == string
{
    return value
}

#test
{
    requiresText(1)     // swc-expected-error {{sema_err_function_where_failed}}
}

interface IConditionalValue
{
    mtd value()->s32
}

struct RejectedConditionalValue
{
    number: s32 = 42
}

impl IConditionalValue for RejectedConditionalValue
{
    mtd value()->s32 where false
    {
        return .number
    }
}

#test
{
    var value: RejectedConditionalValue
    let view:  IConditionalValue = &value     // swc-expected-error {{sema_err_function_where_failed}}
    discard view
}
