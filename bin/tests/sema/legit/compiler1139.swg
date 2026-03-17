#global fileprivate // swc-option sema-only
#global skip
#[Swag.Inline]
func toto()->s32 => 666

//#[Swag.PrintBc]
#test
{
    let x = toto()
    @assert(x == 666)
}
