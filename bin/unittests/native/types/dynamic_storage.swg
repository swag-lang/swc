#global private

#[Swag.DynCast]
struct EmptyDynamicStorage {}

struct EmptyDynamicChild
{
    using base: EmptyDynamicStorage
    value:      s32 = 23
}

func copyEmptyDynamicStorage(value: EmptyDynamicStorage)->EmptyDynamicStorage => value

#test
{
    var owner: EmptyDynamicChild
    var base = copyEmptyDynamicStorage(owner.base)
    Swag.assert(cast #try (*EmptyDynamicChild) &base == null)
    let embedded = &owner.base
    Swag.assert(cast #try (*EmptyDynamicChild) embedded == &owner)
}

#[Swag.DynCast, Swag.Pack(1)]
struct PackedDynamicStorage
{
    value: u8 = 7
}

#test
{
    var value: PackedDynamicStorage
    Swag.assert(#sizeof(PackedDynamicStorage) == 9)
    Swag.assert(#alignof(PackedDynamicStorage) == 1)
    Swag.assert(cast #try (*PackedDynamicStorage) &value == &value)
}

#[Swag.DynCast]
struct StorageBase
{
    value: s32 = 12
}

struct StorageChild
{
    prefix:     u64 = 31
    using base: StorageBase
    extra:      s32 = 45
}

struct StorageContainer
{
    child: StorageChild
}

func checkStorage(value: *void, type: typeinfo)
{
    let info  = cast(const *Swag.TypeInfoStruct) cast(const *void) type
    let slots = info.dynamicSlots!
    Swag.assert(slots.count == 1)
    let slot   = cast([*] u8) value + slots[0].offset
    let stored = (cast(*u64) cast(*void) slot)[]
    Swag.assert(stored == cast(u64) &slots[0])
}

#test
{
    #assert(#sizeof(StorageBase) == 16)
    #assert(#sizeof(StorageChild) == 32)
    var base:      StorageBase
    var child:     StorageChild
    var container: StorageContainer
    checkStorage(&base, StorageBase)
    checkStorage(&child, StorageChild)
    checkStorage(&container.child, StorageChild)
    Swag.assert(child.prefix == 31)
    Swag.assert(child.value == 12)
    Swag.assert(child.extra == 45)
}

#test
{
    var values: [3] StorageChild
    for &value in values do
        checkStorage(value, StorageChild)
}
