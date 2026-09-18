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
    Swag.assert(not (&base is CollectionDynamicChild))
    Reflection.assign(&child.base, &base, CollectionDynamicBase)
    Swag.assert(cast #try (*CollectionDynamicChild) &child.base == &child)
}

#test
{
    var child: CollectionDynamicChild
    child.value = 42
    Reflection.reset(&child.base, CollectionDynamicBase)
    Swag.assert(child.value == 17)
    Swag.assert(cast #try (*CollectionDynamicChild) &child.base == &child)
}

#test
{
    let type: typeinfo = CollectionDynamicChild
    let storage        = Memory.new(type)!
    defer Memory.delete(storage, type)
    let value = cast(*CollectionDynamicChild) storage
    let base: *CollectionDynamicBase = value
    Swag.assert(cast #try (*CollectionDynamicChild) base == value)
    Swag.assert(base.value == 17)
}

#[Swag.DynCast]
struct CollectionSwapBase { value: s32 }

impl CollectionSwapBase
{
    mtd opDrop()
    {
        Swag.assert(cast #try (*CollectionSwapBase) me == me)
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
    Swag.assert(left.value == 42 and right.value == 17)
    Swag.assert(cast #try (*CollectionSwapChild) &left.base == &left)
    Swag.assert(cast #try (*CollectionSwapChild) &right.base == &right)
}

// A base view and an independent value have different identities but equal keys.
#test
{
    var base:  CollectionDynamicBase
    var child: CollectionDynamicChild
    Swag.assert(Hash.hash32(base) == Hash.hash32(child.base))
    Swag.assert(Hash.hash64(base) == Hash.hash64(child.base))
    var values: HashTable'(CollectionDynamicBase, u32)
    values.add(child.base, 42)
    Swag.assert(values.find(base).value == 42)
    values.reserve(64)
    Swag.assert(values.find(child.base).value == 42)
}

#test
{
    var child:  CollectionDynamicChild
    var values: HashTable'(u32, CollectionDynamicBase)
    values.add(1, child.base)
    Swag.assert(not (&values.find(1).value is CollectionDynamicChild))
    values.reserve(64)
    Swag.assert(not (&values.find(1).value is CollectionDynamicChild))
    var copied = values
    Swag.assert(not (&copied.find(1).value is CollectionDynamicChild))
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
    Swag.assert(values.count == 2)
    for &value in values
    {
        Swag.assert(value.value == 17)
        Swag.assert(not (value is CollectionDynamicChild))
    }

    var copied = values
    values.removeAt(0)
    Swag.assert(copied.count == 2)
    Swag.assert(not (&values[0] is CollectionDynamicChild))
    Swag.assert(not (&copied[0] is CollectionDynamicChild))
}

#test
{
    var child:  CollectionDynamicChild
    let baseView = Swag.makeSlice(&child.base, 1)
    var values: StaticArray'(CollectionDynamicBase, 4)
    values.add(baseView)
    values.insertAt(0, baseView)
    Swag.assert(values.count == 2)
    for &value in values
    {
        Swag.assert(value.value == 17)
        Swag.assert(not (value is CollectionDynamicChild))
    }

    values.removeAt(0)
    Swag.assert(not (&values[0] is CollectionDynamicChild))
}
