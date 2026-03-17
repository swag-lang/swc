#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
func T(a: ...) {}

//#[Swag.PrintBc]
#test
{
    T(10, 100)
    T(10, "100")
}
