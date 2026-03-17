//

#global fileprivate


#[Swag.Compiler]
func titi()->bool { return true }

#test
{
    @assert(titi())
}
