// swc-option suite-test

#global fileprivate
using Swag

//#[PrintBc]
func main()->s64
{
    let a: s32 = 666
    @assert(a == 666)
    let b: s64 = 555
    @assert(b == 555)
    return a + b
}

#test
{
    @assert(main() == 1221)
}
