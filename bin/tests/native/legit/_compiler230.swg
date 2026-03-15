// swc-option suite-test

#global fileprivate
using Swag

//#[PrintBc]
func main()->s32
{
    var a = 10
    var b = 0
    while (a > 0)
    {
        a = a - 1; b = b + 1; }

    @assert(a == 0)
    @assert(b == 10)
    return b
}

#test
{
    @assert(main() == 10)
}
