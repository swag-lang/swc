// swc-option suite-test

#global fileprivate

var g = "toto"

//#[Swag.PrintBc]
#test
{
    let c = @countof(g)
    @assert(c == 4)
}
