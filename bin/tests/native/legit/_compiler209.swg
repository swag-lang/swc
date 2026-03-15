// swc-option suite-test

#global fileprivate
using Swag

func main(a: f64, b: f64)->f64
{
    @assert(a == 666)
    @assert(b == 555)
    return a + b
}

#test
{
    @assert(main(666'f64, 555'f64) == 1221.0)
}
