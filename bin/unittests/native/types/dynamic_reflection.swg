#global private

#[Swag.DynCast]
struct ReflectedDynamicValue { value: s32 }

namespace Reflection
{
    // Mirror the public predicate to exercise its compiler-side constant folding.
    #[Swag.ConstExpr]
    func isPod(type: typeinfo?)->bool
    {
        if not type do
            return false
        return type.flags & (Swag.TypeInfoFlags.HasDrop | Swag.TypeInfoFlags.HasPostMove | Swag.TypeInfoFlags.HasPostCopy | Swag.TypeInfoFlags.HasDynamicStorage) ? false : true
    }

    #[Swag.ConstExpr]
    func hasDynamicStorage(type: typeinfo?)->bool => type and (type.flags & Swag.TypeInfoFlags.HasDynamicStorage) ? true : false
}

#test
{
    #assert(not Reflection.isPod(ReflectedDynamicValue))
    #assert(Reflection.hasDynamicStorage(ReflectedDynamicValue))
    #assert(Reflection.hasDynamicStorage(#type [2] ReflectedDynamicValue))
    #assert(not Reflection.hasDynamicStorage(#type *ReflectedDynamicValue))
}
