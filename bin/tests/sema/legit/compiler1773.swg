#global fileprivate // swc-option sema-only
#global skip
func a(x: ...) {}

//#[Swag.PrintBc]
#test
{
    a(0)
}
