struct CrossFileAssignBox
{
    value: s32
}

impl CrossFileAssignBox
{
    mtd(op: Swag.Operator) opAssign(rhs: s32)
        where op == .AddAssign
    {
        .value += rhs
    }
}
