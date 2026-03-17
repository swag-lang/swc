// 

#global fileprivate
#global skip
#[Swag.Compiler]
func titi()->bool { return true }

#test
{
    @assert(titi())
}
