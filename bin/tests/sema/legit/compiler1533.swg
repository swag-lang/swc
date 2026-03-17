#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    let x = cast(rune) "A"
    @assert(x == "A")
}
