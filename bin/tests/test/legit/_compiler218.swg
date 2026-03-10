// swc-option suite-test

#global fileprivate
using Swag

const g: s64 = 5
const h  = 5555
const i  = 1.5

#test
{
    @assert(g == 5)
    @assert(h == 5555)
    @assert(i == 1.5)
}
