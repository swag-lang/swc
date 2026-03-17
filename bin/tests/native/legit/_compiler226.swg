// 

#global fileprivate
using Swag

//#[PrintBc]
func main()->bool
{
    var a: s32
    {
        var b: s64
        var c: s64
    }
    {
        var b: s64
    }
    return true
}

//#[PrintBc]
func main1()->bool
{
    return main()
}

#test
{
    @assert(main1())
}
