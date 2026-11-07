#global private

struct ReverseNoMatch {}

impl ReverseNoMatch
{
    mtd const opEquals(_: u8)->bool => false
    mtd const opCompare(_: u8)->s32 => 0
}

func compareWithoutReverseEquality(text: string, value: ReverseNoMatch)->bool
{
    return text == value     // swc-expected-error {{sema_err_compare_operand_type}}
}

func compareWithoutReverseOrdering(text: string, value: ReverseNoMatch)->bool
{
    return text < value     // swc-expected-error {{sema_err_compare_operand_type}}
}
