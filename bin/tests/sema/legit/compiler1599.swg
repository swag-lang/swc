#global fileprivate
#global skip
#[Swag.Compiler]
func toto()->bool
{
    return true
}

#test
{
    #assert(#run toto()
)
}
