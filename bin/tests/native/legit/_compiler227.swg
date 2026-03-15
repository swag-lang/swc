// swc-option suite-test

#global fileprivate
using Swag

func main()->s32
{
    var a: s32
    var b: s32
    a = 666; b = 100; @assert(a == 666)
    @assert(b == 100)
    a = 500; @assert(a == 500)
    @assert(b == 100)
    return a + b
}

//#[PrintBc]
func main1()->s32
{
    return main()
}

#test
{
    @assert(main1() == 600)
}
