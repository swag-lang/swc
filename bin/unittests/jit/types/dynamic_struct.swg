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
    Swag.require((catch cast(const *DynamicBase?, &wrapper)) == &value)
    Swag.require(not (&wrapper is DynamicBase))
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
    Swag.require((catch cast(*DynamicGrandchild?, base)) == &owner)
    Swag.require(base.value == 23)
    Swag.require(not (&moved is DynamicChild))
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
    Swag.require((catch cast(*ResetDynamicChild?, base)) == &owner)
    Swag.require(not (&moved is ResetDynamicChild))
}

func inspectDynamic(base: *DynamicBase)
{
    let child = catch cast(*DynamicChild?, base)
    Swag.assert(child != null)
    Swag.assert(child.extra == 45)
    Swag.assert(not (base is DynamicSibling))
    let assumed = assume cast (*DynamicChild, base)
    Swag.assert(assumed == child)
}

#test
{
    var value: DynamicGrandchild
    inspectDynamic(&value)
    let base: *DynamicBase = &value
    let grandchild         = catch cast(*DynamicGrandchild?, base)
    Swag.require(grandchild == &value)
    Swag.require(grandchild!.tail == 67)
}

#test
{
    var base: DynamicBase
    Swag.require(not (&base is DynamicChild))
    let absent: *DynamicBase? = null
    Swag.require(not (absent is DynamicChild))
}

#test
{
    var value: DynamicGrandchild
    var copied = value.child.base
    Swag.require(not (&copied is DynamicChild))
    value.child.base = copied
    let base: *DynamicBase = &value
    Swag.require((catch cast(*DynamicGrandchild?, base)) == &value)
    var moved = #move value
    let movedBase: *DynamicBase = &moved
    Swag.require((catch cast(*DynamicGrandchild?, movedBase)) == &moved)
}

func inspectPresentDynamic(base: *DynamicBase?)->bool
{
    while base
    {
        let child = catch cast(*DynamicChild?, base)
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
    Swag.require(inspectPresentDynamic(&child))
    Swag.require(not inspectPresentDynamic(&base))
    Swag.require(not inspectPresentDynamic(null))
}

#test
{
    var value: DynamicGrandchild
    var copied = copyDynamicBase(value.child.base)
    Swag.require(not (&copied is DynamicChild))
    Swag.require(copied.value == 12)
    var values: [3] DynamicGrandchild
    var copies = values
    copies = values
    for &item in copies
    {
        let base: *DynamicBase = item
        Swag.require((catch cast(*DynamicGrandchild?, base)) == item)
    }
}

#test
{
    var pair:   DynamicPair
    let first:  *DynamicBase = &pair.first
    let second: *DynamicBase = &pair.second
    Swag.require((catch cast(*DynamicChild?, first)) == &pair.first)
    Swag.require((catch cast(*DynamicChild?, second)) == &pair.second)
    Swag.require(assume cast (*DynamicChild, second) == &pair.second)
    Swag.require(assume cast (*DynamicPair, second) == &pair)
    Swag.require(cast(*DynamicBase?, second) == second)
}
