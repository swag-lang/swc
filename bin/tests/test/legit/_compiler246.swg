// swc-option suite-test

#global fileprivate
using Swag

//#[PrintBc]
func main(a: s32 = 6)
{
    @assert(a == 6)
}

//#[PrintBc]
func main1()
{
    main()
}

#test
{
    main1()
}
