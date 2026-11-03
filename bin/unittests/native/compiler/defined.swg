#global private
const GlobalValue = 1

namespace Scope
{
    const NestedValue = 2
}

#assert(#defined(GlobalValue))
#assert(#defined(Scope.NestedValue))
#assert(not #defined(MissingValue))
#assert(#defined(ForwardDefined))
const ForwardDefined = 3

// #defined checks local and global symbols
#test
{
    const LocalConst = 4
    #assert(#defined(LocalConst))

    Swag.require(GlobalValue == 1)
    Swag.require(Scope.NestedValue == 2)
    Swag.require(ForwardDefined == 3)
    Swag.require(LocalConst == 4)
}
