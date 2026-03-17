#global fileprivate // swc-option sema-only
#global skip
func F(a: s32 = 10, b: s32 = 20)
{
    @assert(a == 10)
    @assert(b == 666)
}

//#[Swag.PrintBc]
#test
{
    F(b: 666)
}
