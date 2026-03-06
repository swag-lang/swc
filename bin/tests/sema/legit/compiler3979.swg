#global fileprivate
#global skip
func toto(x: const &s32)
{
    @assert(x == 2)
}

//#[Swag.PrintBc]
#test
{
    toto(2)
}
