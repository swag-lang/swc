#global if #command == Swag.CompilerCommand.Test
#global private

#[Swag.DynCast]
struct CollectionDynamicBase { value: s32 = 17 }

struct CollectionDynamicChild
{
    using base: CollectionDynamicBase
    extra:      s32 = 42
}

#test
{
    var child: CollectionDynamicChild
    var base:  CollectionDynamicBase
    Reflection.assign(&base, &child.base, CollectionDynamicBase)
    Swag.require(not (&base is CollectionDynamicChild))
    Reflection.assign(&child.base, &base, CollectionDynamicBase)
    Swag.require((catch cast(*CollectionDynamicChild?, &child.base)) == &child)
}

#test
{
    var child: CollectionDynamicChild
    child.value = 42
    Reflection.reset(&child.base, CollectionDynamicBase)
    Swag.require(child.value == 17)
    Swag.require((catch cast(*CollectionDynamicChild?, &child.base)) == &child)
}

#test
{
    let type: typeinfo = CollectionDynamicChild
    let storage        = Memory.new(type)
    defer Memory.delete(storage, type)
    let value = cast(*CollectionDynamicChild, storage)
    let base: *CollectionDynamicBase = value
    Swag.require((catch cast(*CollectionDynamicChild?, base)) == value)
    Swag.require(base.value == 17)
}

#[Swag.DynCast]
struct CollectionSwapBase { value: s32 }

impl CollectionSwapBase
{
    mtd opDrop()
    {
        Swag.require(cast(*CollectionSwapBase?, me) == me)
    }
}

struct CollectionSwapChild { using base: CollectionSwapBase }

#test
{
    var left:  CollectionSwapChild
    var right: CollectionSwapChild
    left.value  = 17
    right.value = 42
    swap(&left.base, &right.base)
    Swag.require(left.value == 42 and right.value == 17)
    Swag.require((catch cast(*CollectionSwapChild?, &left.base)) == &left)
    Swag.require((catch cast(*CollectionSwapChild?, &right.base)) == &right)
}

// A base view and an independent value have different identities but equal keys.
#test
{
    var base:  CollectionDynamicBase
    var child: CollectionDynamicChild
    Swag.require(Hash.hash32(base) == Hash.hash32(child.base))
    Swag.require(Hash.hash64(base) == Hash.hash64(child.base))
    var values: HashTable'(CollectionDynamicBase, u32)
    values.add(child.base, 42)
    Swag.require(values.find(base).value == 42)
    values.reserve(64)
    Swag.require(values.find(child.base).value == 42)
}

#test
{
    var child:  CollectionDynamicChild
    var values: HashTable'(u32, CollectionDynamicBase)
    values.add(1, child.base)
    Swag.require(not (&values.find(1).value is CollectionDynamicChild))
    values.reserve(64)
    Swag.require(not (&values.find(1).value is CollectionDynamicChild))
    var copied = values
    Swag.require(not (&copied.find(1).value is CollectionDynamicChild))
}

#test
{
    #assert(Reflection.hasDynamicStorage(CollectionDynamicBase))
    #assert(Reflection.hasDynamicStorage(#type [2] CollectionDynamicChild))
    #assert(not Reflection.hasDynamicStorage(#type *CollectionDynamicChild))
    #assert(not Reflection.isPod(CollectionDynamicBase))

    var child:  CollectionDynamicChild
    let baseView = Swag.makeSlice(&child.base, 1)
    var values: Array'CollectionDynamicBase
    values.add(baseView)
    values.insertAt(0, baseView)
    values.reserve(64)
    Swag.require(values.count == 2)
    for &value in values
    {
        Swag.require(value.value == 17)
        Swag.require(not (value is CollectionDynamicChild))
    }

    var copied = values
    values.removeAt(0)
    Swag.require(copied.count == 2)
    Swag.require(not (&values[0] is CollectionDynamicChild))
    Swag.require(not (&copied[0] is CollectionDynamicChild))
}

#test
{
    var child:  CollectionDynamicChild
    let baseView = Swag.makeSlice(&child.base, 1)
    var values: StaticArray'(CollectionDynamicBase, 4)
    values.add(baseView)
    values.insertAt(0, baseView)
    Swag.require(values.count == 2)
    for &value in values
    {
        Swag.require(value.value == 17)
        Swag.require(not (value is CollectionDynamicChild))
    }

    values.removeAt(0)
    Swag.require(not (&values[0] is CollectionDynamicChild))
}
