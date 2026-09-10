#global private
using Swag

// A type that owns a release states no copy, and a 'where' constraint lets a generic type
// decide per instantiation. Reflection answers both from the same facts.

var DropCount: s32

struct Owning
{
    value: s32
}

impl Owning
{
    mtd opDrop()
    {
        DropCount += 1
    }
}

struct Duplicable
{
    value: s32
}

impl Duplicable
{
    mtd opDrop() {}

    mtd opPostCopy()
    {
        .value += 1
    }
}

struct OwningMember
{
    inner: Owning
}

struct DuplicableMember
{
    inner: Duplicable
}

namespace LifecycleOwningCopy.Reflection
{
    #[ConstExpr, Inline]
    {
        func canCopy(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.CanCopy) ? true : false
    }
}

// Declaring 'opDrop' without 'opPostCopy' takes the copy away, and a member that owns a
// release takes it away from the enclosing type too.
#test
{
    #assert(not LifecycleOwningCopy.Reflection.canCopy(#typeof(Owning)))
    #assert(LifecycleOwningCopy.Reflection.canCopy(#typeof(Duplicable)))
    #assert(not LifecycleOwningCopy.Reflection.canCopy(#typeof(OwningMember)))
    #assert(LifecycleOwningCopy.Reflection.canCopy(#typeof(DuplicableMember)))
}

#test
{
    let owning:     typeinfo = #typeof(Owning)
    let duplicable: typeinfo = #typeof(Duplicable)
    let owner:      typeinfo = #typeof(OwningMember)
    Swag.assert((owning.flags & Swag.TypeInfoFlags.CanCopy) == .Zero)
    Swag.assert((owner.flags & Swag.TypeInfoFlags.CanCopy) == .Zero)
    Swag.assert((duplicable.flags & Swag.TypeInfoFlags.CanCopy) != .Zero)
}

// '#move' hands an owning value over, and the resource is released exactly once.
#test
{
    DropCount = 0
    {
        var a = Owning{7}
        var b = #move a
        Swag.assert(b.value == 7)
    }

    Swag.assert(DropCount == 1)
}

// 'opPostCopy' states what a duplicate owns, and opts the copy back in.
#test
{
    var a = Duplicable{4}
    let b = a
    Swag.assert(b.value == 5)
    Swag.assert(a.value == 4)

    var c: DuplicableMember = {{10}}
    let d = c
    Swag.assert(d.inner.value == 11)
}
