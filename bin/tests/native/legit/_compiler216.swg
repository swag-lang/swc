// 

#global fileprivate
using Swag

//#[PrintBc]
func main()->bool
{
    if false
    {
        @assert(false)
    }
    else
    {
        @assert(true)
    }

    @assert(true)
    return true
}

#test
{
    @assert(main())
}
