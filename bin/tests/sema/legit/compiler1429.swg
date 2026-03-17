#global fileprivate // swc-option sema-only
#global skip
struct A
{
    x:   s64 = 10
}

//#[Swag.PrintBc]
func toto(x: A)
{
    return
}
