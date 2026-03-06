#global fileprivate
#global skip
//#[Swag.PrintBc]
#test
{
    var x = 10
    @init(&x, 1)(0)
    @assert(x == 0)
}
