#global fileprivate

var g = "toto"

//#[Swag.PrintBc]
#run
{
    let c = @countof(g)
    @assert(c == 4)
}
