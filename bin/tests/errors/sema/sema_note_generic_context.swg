#global fileprivate

struct NoGenericCompare {}

func(T) genericCompare(lhs, rhs: T)->s32 // swc-expected-note {{sema_note_generic_context}}
{
    return lhs <=> rhs // swc-expected-error {{sema_err_compare_operand_type}}
}

struct(T) GenericCompareBox // swc-expected-note {{sema_note_generic_context}}
{
    value: T
}

impl GenericCompareBox
{
    mtd const compareValue()->s32
    {
        return .value <=> .value // swc-expected-error {{sema_err_compare_operand_type}}
    }
}

#test
{
    let lhs = NoGenericCompare{}
    let rhs = NoGenericCompare{}
    genericCompare(lhs, rhs)
}

#test
{
    let box: GenericCompareBox'NoGenericCompare = {value: NoGenericCompare{}}
    box.compareValue()
}
