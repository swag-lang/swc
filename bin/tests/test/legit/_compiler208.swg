// swc-option suite-test

#global fileprivate
using Swag

func main(a: s64)
{
    @assert(a == 666)
}

#test
{
    main(666's64)
}
