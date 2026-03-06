#global fileprivate
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
