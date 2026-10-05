#global private

#[Swag.Inline]
func rejectedOperatorDependency()
{
    discard cast(*void) true     // swc-expected-error {{sema_err_cannot_cast}}
}

struct OperatorErrorText {}

impl OperatorErrorText
{
    mtd(op: Swag.Operator) opAssign(value: string)
        where op == .AddAssign
    {
        rejectedOperatorDependency()
    }
}

// A failed specialization is not an absent operator. Keep the dependency's
// diagnostic instead of claiming that this valid operand type cannot be added.
#test
{
    var value: OperatorErrorText
    value += "abc"
}
