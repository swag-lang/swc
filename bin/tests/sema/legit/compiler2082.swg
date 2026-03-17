#global fileprivate // swc-option sema-only
#global skip
struct AA {}

#[Swag.Inline]
func toto()->AA
{
    return AA{}
}

//#[Swag.PrintBc]
#test
{
    var ex = toto()
}
