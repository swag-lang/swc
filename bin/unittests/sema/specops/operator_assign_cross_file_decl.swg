struct CrossFileAssignBox
{
    value: s32
}

impl CrossFileAssignBox
{
    mtd(op: string) opAssign(rhs: s32)
    {
        #if op == "+=" do
            .value += rhs
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }
}
