// swc-option suite-test

#global fileprivate
using Swag

//#[PrintBc]
func main()->s32
{
    var a: s32
    {
        var b: s32
        a = 666; b = 100; }
    @assert(a == 666)
    return a
}

#test
{
    @assert(main() == 666)
}
