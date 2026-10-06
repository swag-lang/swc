#global private

// A top-level run waits for the declarations that follow it, and runs after the walk has left
// its attribute list: it must still see the attributes written on it.
func failing()->bool => false

#run
{
    Swag.assert(not failing())
}

#[Swag.Safety(.Assert, false)]
#run
{
    Swag.assert(failing())
}

#[Swag.Safety(.Assert, false)]
#ast
{
    Swag.assert(failing())
    return "const DeferredAstRan = true"
}

#test
{
    #assert(DeferredAstRan)
}
