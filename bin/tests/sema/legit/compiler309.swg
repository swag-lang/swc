#global fileprivate
#global skip
//#[Swag.PrintBc]
#test
{
    let c = "toto"
    @assert(c == "toto")
    @assert(c != "titi")
}
