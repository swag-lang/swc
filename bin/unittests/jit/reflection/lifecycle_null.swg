#global private

namespace Reflection
{
    // Mirror the public predicates so this file also exercises compiler-side folding.
    #[Swag.ConstExpr]
    func isPod(type: typeinfo?)->bool
    {
        if not type do
            return false
        return type.flags & (Swag.TypeInfoFlags.HasDrop |
                             Swag.TypeInfoFlags.HasPostMove |
                             Swag.TypeInfoFlags.HasPostCopy |
                             Swag.TypeInfoFlags.HasDynamicStorage) ? false : true
    }

    #[Swag.ConstExpr]
    func canCopy(type: typeinfo?)->bool => type and (type.flags & Swag.TypeInfoFlags.CanCopy) ? true : false
}

// A missing descriptor is not the descriptor of the null-pointer type.
#test
{
    const Missing: typeinfo? = null
    #assert(not Reflection.isPod(null))
    #assert(not Reflection.isPod(Missing))
    #assert(not Reflection.isPod(cast(typeinfo?, null)))
    #assert(not Reflection.canCopy(null))
    #assert(not Reflection.canCopy(Missing))
    #assert(not Reflection.canCopy(cast(typeinfo?, null)))
    #assert(Reflection.isPod(#typeof(null)))
    #assert(Reflection.canCopy(u32))
    #assert(Reflection.isPod(u32))

    Swag.assert(not Reflection.isPod(null))
    Swag.assert(not Reflection.canCopy(null))
    Swag.assert(Reflection.isPod(#typeof(null)))
}
