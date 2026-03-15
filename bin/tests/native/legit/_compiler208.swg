// swc-option suite-test

#global fileprivate
using Swag

func main(a: s64)->s64
{
    @assert(a == 666)
    return a
}

#test
{
    @assert(main(666's64) == 666)
}
