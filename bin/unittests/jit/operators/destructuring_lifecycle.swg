#global private

// A destructured field that lands in storage of its own was copied bit for bit, so its lifecycle
// hook must run exactly as for a single declaration: 'opPostMove' when the source is a temporary,
// whatever error-management keyword wraps it and whether or not the temporary has a drop, and
// 'opPostCopy' when the source is a named value that keeps its field.

var DestructuringDrops: s32

// Points at its own storage: only the post-move and post-copy hooks keep the pointer right.
struct DestructuringSelfRef
{
    ptr:     *s32?
    storage: s32
}

impl DestructuringSelfRef
{
    mtd opPostMove() { .ptr = &.storage }
    mtd opPostCopy() { .ptr = &.storage }
    mtd const isValid()->bool => .ptr == &.storage
}

// The same shape with a drop, so the temporary owning it carries a drop of its own.
struct DestructuringOwner
{
    ptr:     *s32?
    storage: s32
}

impl DestructuringOwner
{
    mtd opPostMove() { .ptr = &.storage }
    mtd opPostCopy() { .ptr = &.storage }
    mtd opDrop()
    {
        if .storage != 0 do
            DestructuringDrops += 1
    }

    mtd const isValid()->bool => .ptr == &.storage
}

func(T) makeDestructuringValue(value: s32)->T
{
    var result: retval
    result.storage = value
    result.ptr     = &result.storage
    return result
}

func(T) makeDestructuringPair()->{ first: T, count: u32 }
{
    var result: retval
    result.first = makeDestructuringValue'T(5)
    result.count = 9
    return result
}

func(T) makeDestructuringPairFail()->{ first: T, count: u32 } fail
{
    var result: retval
    result.first = makeDestructuringValue'T(6)
    result.count = 9
    return result
}

#test
{
    let {first, count} = makeDestructuringPair'DestructuringSelfRef()
    Swag.assert(first.isValid() and count == 9)

    let {first: caught} = catch makeDestructuringPairFail'DestructuringSelfRef()
    Swag.assert(caught.isValid())

    let {first: expected} = expect makeDestructuringPairFail'DestructuringSelfRef()
    Swag.assert(expected.isValid())
}

#test
{
    DestructuringDrops = 0
    {
        let {first: owned} = makeDestructuringPair'DestructuringOwner()
        Swag.assert(owned.isValid())
        let {first: caught} = catch makeDestructuringPairFail'DestructuringOwner()
        Swag.assert(caught.isValid())
    }

    Swag.assert(DestructuringDrops == 2)
}

#test
{
    DestructuringDrops = 0
    {
        let pair           = makeDestructuringPair'DestructuringOwner()
        let {first, count} = pair
        Swag.assert(first.isValid() and pair.first.isValid())
        Swag.assert(count == 9)
    }

    // The named source keeps its field, so both copies are dropped.
    Swag.assert(DestructuringDrops == 2)
}
