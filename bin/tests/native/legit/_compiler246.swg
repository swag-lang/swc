// swc-option suite-test

#global fileprivate
using Swag

//#[PrintBc]
func main(a: s32 = 6)->s32
{
    @assert(a == 6)
    return a
}

//#[PrintBc]
func main1()->s32
{
    return main()
}

#test
{
    @assert(main1() == 6)
}
