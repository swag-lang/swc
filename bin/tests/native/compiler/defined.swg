#global fileprivate // swc-option suite-test

const GlobalValue = 1

namespace Scope
{
    const NestedValue = 2
}

#assert(#defined(GlobalValue))
#assert(#defined(Scope.NestedValue))
#assert(!#defined(MissingValue))
#assert(#defined(ForwardDefined))
const ForwardDefined = 3

#test
{
    const LocalConst = 4
    #assert(#defined(LocalConst))

    @assert(GlobalValue == 1)
    @assert(Scope.NestedValue == 2)
    @assert(ForwardDefined == 3)
    @assert(LocalConst == 4)
}
