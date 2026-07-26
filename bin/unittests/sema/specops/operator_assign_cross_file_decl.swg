struct CrossFileAssignBox
{
    value: s32
}

impl CrossFileAssignBox
{
    mtd(op: Swag.Operator) opAssign(rhs: s32)
    {
        #static if op == .AddAssign do
            .value += rhs
        else do
            #error("unsupported opAssign op [[" ++ op.symbol() ++ "]]")
    }
}
