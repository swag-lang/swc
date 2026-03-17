#global fileprivate // swc-option sema-only
#global skip
interface I
{
}
struct A {}
struct B {}
impl I for A
{
}

//#[Swag.PrintBc]
#test
{
    let a:   A
    let itf: I = a
    @assert(itf is A)
    @assert(!itf is B)
}
