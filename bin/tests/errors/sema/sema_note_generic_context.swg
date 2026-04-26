#global fileprivate

struct NoGenericCompare {} // swc-expected-help {{sema_help_missing_spec_op}}

func(T) genericCompare(lhs, rhs: T)->s32 // swc-expected-note {{sema_note_generic_context}}
{
    return lhs <=> rhs // swc-expected-error {{sema_err_compare_operand_type}}
}

// swc-expected-help@+1 {{sema_help_missing_spec_op}}
struct(T) GenericCompareBox // swc-expected-note {{sema_note_generic_context}}
{
    value: T
}

impl GenericCompareBox
{
    mtd const compareValue()->s32
    {
        return me <=> me // swc-expected-error {{sema_err_compare_operand_type}}
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
