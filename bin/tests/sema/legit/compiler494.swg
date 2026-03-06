#global fileprivate
#global skip
func T()->string { return "toto"; }

//#[Swag.PrintBc]
#test
{
    @assert(T() == "toto")
}
