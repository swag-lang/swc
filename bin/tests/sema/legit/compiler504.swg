#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
func T(a: ...)
{
    @assert(@countof(a) == 3)
}

//#[Swag.PrintBc]
#test
{
    T(10, 100, 666)
}
