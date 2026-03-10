// swc-option suite-test

#global fileprivate
using Swag

#test
{
    @assert(((2's64 + 4) * 2) == 12)
}
