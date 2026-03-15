// swc-option suite-test

#global fileprivate
using Swag

func main()->bool
{
    @assert(true)
    return true
}

#test
{
    @assert(main())
}
