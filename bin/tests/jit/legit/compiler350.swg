#global fileprivate // swc-option suite-jit
#global skip
//#[Swag.PrintBc]
#test
{
    const a = 666
    let b   = #run a
    @assert(b == 666)
}
