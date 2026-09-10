#global private
using Swag

// A '#static if' gating a method on a reflected property of another type, where that type
// reaches back - through a pointer - to a struct holding the gated one by value. Answering the
// condition must not need the runtime 'TypeInfo' of the whole graph: materializing it waits on
// the struct the condition is gating, and the ring never opens.

namespace StaticIfReflectCycle.Reflection
{
    #[ConstExpr, Inline]
    {
        func canCopy(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.CanCopy) ? true : false
        func hasDrop(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasDrop) ? true : false
    }
}

struct Pool
{
    count: s32
}

impl Pool
{
    #static if StaticIfReflectCycle.Reflection.canCopy(Leaf)
    {
        mtd whenCopyable()->s32 => 1
    }
    else
    {
        mtd whenNot()->s32 => 2
    }
}

struct Leaf
{
    owner: *Holder?
    value: s32
}

struct Holder
{
    items: Pool
}

// The same ring through a generic instance, which is the shape the standard containers use.
struct(T) GenericPool
{
    count: s32
}

impl GenericPool
{
    #static if StaticIfReflectCycle.Reflection.canCopy(T)
    {
        mtd gated()->s32 => 3
    }
}

struct GenericLeaf
{
    owner: *GenericHolder?
    value: s32
}

struct GenericHolder
{
    items: GenericPool'GenericLeaf
}

#test
{
    var holder: Holder
    #assert(#defined(holder.items.whenCopyable))
    #assert(not #defined(holder.items.whenNot))
    Swag.assert(holder.items.whenCopyable() == 1)
}

#test
{
    var holder: GenericHolder
    #assert(#defined(holder.items.gated))
    Swag.assert(holder.items.gated() == 3)
}
