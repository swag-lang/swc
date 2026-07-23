#global private
using Swag

struct PlainValue
{
    value: u32
}

struct DroppableValue
{
    value: u32
}

impl DroppableValue
{
    mtd opDrop() {}
}

func(T) acceptsCopyable(value: T)->bool
    where ReflectionLifecycleWhere.Reflection.canCopy(T)
{
    discard value
    return true
}

func(T) acceptsDroppable()->bool
    where ReflectionLifecycleWhere.Reflection.hasDrop(T)
{
    return true
}

struct(T) GenericBox {}

impl GenericBox
{
    mtd copyOnly(value: T)->bool
        where ReflectionLifecycleWhere.Reflection.canCopy(T)
    {
        discard value
        return true
    }

    mtd callCopyOnly(value: T)->bool
    {
        return .copyOnly(value)
    }
}

namespace ReflectionLifecycleWhere.Reflection
{
    #[ConstExpr, Inline]
    {
        func hasDrop(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasDrop) ? true : false
        func canCopy(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.CanCopy) ? true : false
    }
}

func semaTestReflectionLifecycleWhere()
{
    var plain = PlainValue{1}
    var box: GenericBox'PlainValue
    @assert(acceptsCopyable(plain))
    @assert(acceptsDroppable'DroppableValue())
    @assert(box.callCopyOnly(plain))
}
