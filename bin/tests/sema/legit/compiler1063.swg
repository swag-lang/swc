#global fileprivate // swc-option sema-only
#global skip
func(T) add(value1: T, value2: T) {}

//#[Swag.PrintBc]
#test
{
    add's32(1, 1)
}
