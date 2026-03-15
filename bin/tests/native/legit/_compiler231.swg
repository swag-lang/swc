// swc-option suite-test

#global fileprivate
using Swag

//#[PrintBc]
func main()->f64
{
    var a = 10
    a += 1; @assert(a == 11)

    var b = 1.0'f64
    b += 1.5'f64; @assert(b == 2.5)
    return cast(f64) a + b
}

#test
{
    @assert(main() == 13.5)
}
