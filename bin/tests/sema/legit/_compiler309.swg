#global fileprivate

//#[Swag.PrintBc]
#run
{
    let c = "toto"
    @assert(c == "toto")
    @assert(c != "titi")
}
