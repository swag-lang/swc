#global private

#[Swag.DynCast]
struct DynamicBase
{
    value: s32 = 12
}

struct DynamicChild
{
    prefix:     u64 = 31
    using base: DynamicBase
    extra:      s32 = 45
}

struct DynamicGrandchild
{
    using child: DynamicChild
    tail:        s32 = 67
}

struct DynamicSibling
{
    using base: DynamicBase
}

struct DynamicPair
{
    using first:  DynamicChild
    using second: DynamicChild
}

struct ReadOnlyDynamicWrapper
{
    using base: const *DynamicBase
}

#test
{
    var value: DynamicBase
    var wrapper = ReadOnlyDynamicWrapper{&value}
    Swag.assert(cast #try (const *DynamicBase) &wrapper == &value)
    Swag.assert(cast #try (*DynamicBase) &wrapper == null)
}

func copyDynamicBase(value: DynamicBase)->DynamicBase
{
    return value
}

#test
{
    var owner: DynamicGrandchild
    let base  = &owner.child.base
    var moved = #relocate base[]
    base[] = DynamicBase{value: 23}
    Swag.assert(cast #try (*DynamicGrandchild) base == &owner)
    Swag.assert(base.value == 23)
    Swag.assert(cast #try (*DynamicChild) &moved == null)
}

#[Swag.DynCast]
struct ResetDynamicBase { value: s32 = 7 }

impl ResetDynamicBase
{
    mtd opDrop() {}
}

struct ResetDynamicChild
{
    using base: ResetDynamicBase
    extra:      s32
}

#test
{
    var owner: ResetDynamicChild
    let base  = &owner.base
    var moved = #move base[]
    Swag.assert(cast #try (*ResetDynamicChild) base == &owner)
    Swag.assert(cast #try (*ResetDynamicChild) &moved == null)
}

func inspectDynamic(base: *DynamicBase)
{
    let child = cast #try (*DynamicChild) base
    Swag.assert(child != null)
    Swag.assert(child.extra == 45)
    Swag.assert(cast #try (*DynamicSibling) base == null)
    let assumed = cast #assume (*DynamicChild) base
    Swag.assert(assumed == child)
}

#test
{
    var value: DynamicGrandchild
    inspectDynamic(&value)
    let base: *DynamicBase = &value
    let grandchild         = cast #try (*DynamicGrandchild) base
    Swag.assert(grandchild == &value)
    Swag.assert(grandchild!.tail == 67)
}

#test
{
    var base: DynamicBase
    Swag.assert(cast #try (*DynamicChild) &base == null)
    let absent: *DynamicBase? = null
    Swag.assert(cast #try (*DynamicChild) absent == null)
}

#test
{
    var value: DynamicGrandchild
    var copied = value.child.base
    Swag.assert(cast #try (*DynamicChild) &copied == null)
    value.child.base = copied
    let base: *DynamicBase = &value
    Swag.assert(cast #try (*DynamicGrandchild) base == &value)
    var moved = #move value
    let movedBase: *DynamicBase = &moved
    Swag.assert(cast #try (*DynamicGrandchild) movedBase == &moved)
}

func inspectPresentDynamic(base: *DynamicBase?)->bool
{
    while base
    {
        let child = cast #try (*DynamicChild) base
        if child and child.extra == 45 do
            return true
        return false
    }
    return false
}

#test
{
    var child: DynamicChild
    var base:  DynamicBase
    Swag.assert(inspectPresentDynamic(&child))
    Swag.assert(not inspectPresentDynamic(&base))
    Swag.assert(not inspectPresentDynamic(null))
}

#test
{
    var value: DynamicGrandchild
    var copied = copyDynamicBase(value.child.base)
    Swag.assert(cast #try (*DynamicChild) &copied == null)
    Swag.assert(copied.value == 12)
    var values: [3] DynamicGrandchild
    var copies = values
    copies = values
    for &item in copies
    {
        let base: *DynamicBase = item
        Swag.assert(cast #try (*DynamicGrandchild) base == item)
    }
}

#test
{
    var pair:   DynamicPair
    let first:  *DynamicBase = &pair.first
    let second: *DynamicBase = &pair.second
    Swag.assert(cast #try (*DynamicChild) first == &pair.first)
    Swag.assert(cast #try (*DynamicChild) second == &pair.second)
    Swag.assert(cast #assume (*DynamicChild) second == &pair.second)
    Swag.assert(cast #assume (*DynamicPair) second == &pair)
    Swag.assert(cast #try (*DynamicBase) second == second)
}
