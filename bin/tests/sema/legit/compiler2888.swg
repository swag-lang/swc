#global fileprivate
#global skip
#[Swag.Tls]
var G: string = "titi"

//#[Swag.PrintBc]
#test
{
    @assert(G == "titi")
}
