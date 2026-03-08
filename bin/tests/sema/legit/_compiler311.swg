#global fileprivate

var g: string

//#[Swag.PrintBc]
#run
{
    g = "toto"; @assert(g == "toto")
    g = "titi"; @assert(g == "titi")
    //@print(g);
}
