#global fileprivate // swc-option sema-only
#global skip
#[Swag.Inline, Swag.Overload]
func(T) toto()
    where true
{
}

#[Swag.Inline, Swag.Overload]
func(T) toto()
    where false
{
}

//#[Swag.PrintBc]
#test
{
    toto's32()
}
