#global fileprivate // swc-option sema-only
#global skip
func titi() throw
{
    throw Swag.BaseError{"toto"}
}

//#[Swag.PrintBc]
func toto()
{
    assume titi()
}

#test
{
}
