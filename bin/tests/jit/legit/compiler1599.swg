#global fileprivate // swc-option suite-jit
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
