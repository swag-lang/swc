#global fileprivate // swc-option sema-only
#global skip
const TOTO = 666

//#[Swag.PrintBc]
#test
{
    let b = TOTO
    @assert(b == 666)
}
