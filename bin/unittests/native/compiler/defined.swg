#global private
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

// #defined checks local and global symbols
#test
{
    const LocalConst = 4
    #assert(#defined(LocalConst))

    Swag.assert(GlobalValue == 1)
    Swag.assert(Scope.NestedValue == 2)
    Swag.assert(ForwardDefined == 3)
    Swag.assert(LocalConst == 4)
}
