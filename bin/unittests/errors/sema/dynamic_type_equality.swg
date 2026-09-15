#global private

func compareBoxedWithType(value: any)->bool
{
    // swc-expected-error@(+1) {{sema_err_compare_operand_type}}
    return value == s32
}

func compareTypeWithBoxed(value: any, type: typeinfo)->bool
{
    // swc-expected-error@(+1) {{sema_err_compare_operand_type}}
    return type != value
}
