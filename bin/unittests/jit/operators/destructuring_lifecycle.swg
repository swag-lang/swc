#global private

// A destructured field that lands in storage of its own was copied bit for bit, so its lifecycle
// hook must run exactly as for a single declaration: 'opPostMove' when the source is a temporary,
// whatever error-management keyword wraps it and whether or not the temporary has a drop, and
// 'opPostCopy' when the source is a named value that keeps its field.

var DestructuringDrops:   s32
var DestructuringDropSum: s32
var DestructuringCopies:  s32

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
    mtd opPostCopy()
    {
        if .ptr do
            .storage = .ptr[]
        .ptr = &.storage
        DestructuringCopies += 1
    }
    mtd opDrop()
    {
        if .storage != 0
        {
            DestructuringDrops   += 1
            DestructuringDropSum += .storage
            .storage = 0
        }
    }

    mtd const isValid()->bool => .ptr == &.storage
}

func(T) makeDestructuringValue(value: s32)->T
{
    var result: #returntype
    result.storage = value
    result.ptr     = &result.storage
    return result
}

func(T) makeDestructuringPair()->{ first: T, count: u32 }
{
    var result: #returntype
    result.first = makeDestructuringValue'T(5)
    result.count = 9
    return result
}

func(T) makeDestructuringPairFail()->{ first: T, count: u32 } fail
{
    var result: #returntype
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
    scope
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
    scope
    {
        let pair = makeDestructuringPair'DestructuringOwner()
        let {first, count} = pair
        Swag.assert(first.isValid() and pair.first.isValid())
        Swag.assert(count == 9)
    }

    // The named source keeps its field, so both copies are dropped.
    Swag.assert(DestructuringDrops == 2)
}

func makeDestructuringOwners()->{kept: DestructuringOwner, skipped: DestructuringOwner}
{
    var result: #returntype
    result.kept    = makeDestructuringValue'DestructuringOwner(7)
    result.skipped = makeDestructuringValue'DestructuringOwner(8)
    return result
}

#test
{
    DestructuringDrops = 0
    scope
    {
        let {kept: value} = makeDestructuringOwners()
        Swag.assert(value.isValid())
        Swag.assert(DestructuringDrops == 1)
    }
    Swag.assert(DestructuringDrops == 2)
}

#test
{
    DestructuringDrops = 0
    let {kept: _, skipped: _} = makeDestructuringOwners()
    Swag.assert(DestructuringDrops == 2)
}

func makeReorderedDestructuringOwners()->{skipped: DestructuringOwner, kept: DestructuringOwner}
{
    var result: #returntype
    result.skipped = makeDestructuringValue'DestructuringOwner(70)
    result.kept    = makeDestructuringValue'DestructuringOwner(80)
    return result
}

#test
{
    DestructuringDrops = 0
    scope
    {
        let value: {kept: DestructuringOwner, skipped: DestructuringOwner} = makeReorderedDestructuringOwners()
        Swag.assert(value.kept.isValid() and value.skipped.isValid())
    }
    Swag.assert(DestructuringDrops == 2)
}

#test
{
    DestructuringDrops   = 0
    DestructuringDropSum = 0
    scope
    {
        var value = {kept: makeDestructuringValue'DestructuringOwner(1), skipped: makeDestructuringValue'DestructuringOwner(2)}
        value = makeReorderedDestructuringOwners()
        Swag.assert(value.kept.isValid() and value.skipped.isValid())
        Swag.assert(DestructuringDropSum == 3)
    }
    Swag.assert(DestructuringDrops == 4 and DestructuringDropSum == 153)
}

#test
{
    DestructuringDrops  = 0
    DestructuringCopies = 0
    scope
    {
        let source = makeReorderedDestructuringOwners()
        let value: {kept: DestructuringOwner, skipped: DestructuringOwner} = source
        Swag.assert(value.kept.isValid() and value.skipped.isValid())
        Swag.assert(source.kept.isValid() and source.skipped.isValid())
        Swag.assert(DestructuringCopies == 2)
    }
    Swag.assert(DestructuringDrops == 4)
}

impl DestructuringOwner
{
    mtd const opEquals(other: DestructuringOwner)->bool => .storage == other.storage
}

#test
{
    DestructuringDrops  = 0
    DestructuringCopies = 0
    scope
    {
        let left  = {first: makeDestructuringValue'DestructuringOwner(1), second: makeDestructuringValue'DestructuringOwner(2)}
        let right = {second: makeDestructuringValue'DestructuringOwner(2), first: makeDestructuringValue'DestructuringOwner(1)}
        Swag.assert(left == right)
        Swag.assert(DestructuringCopies == 0 and DestructuringDrops == 0)
    }
    Swag.assert(DestructuringDrops == 4)
}

#[Swag.NoCopy]
struct TupleRecordHandle { value: s32 }

impl TupleRecordHandle
{
    mtd opDrop() {}
    mtd const opEquals(other: TupleRecordHandle)->bool => .value == other.value
}

#test
{
    let left  = {handle: TupleRecordHandle{7}, count: 2}
    let right = {count: 2, handle: TupleRecordHandle{7}}
    Swag.assert(left == right)
}

#test
{
    let source  = {handle: TupleRecordHandle{7}, count: 2}
    let {count} = source
    Swag.assert(count == 2 and source.handle.value == 7)
}

#test
{
    DestructuringDrops   = 0
    DestructuringDropSum = 0
    DestructuringCopies  = 0
    scope
    {
        var source = makeReorderedDestructuringOwners()
        let {kept} = #move source
        Swag.assert(kept.isValid() and kept.storage == 80)
        Swag.assert(DestructuringCopies == 0)
        Swag.assert(source.kept.storage == 0 and source.skipped.storage == 0)
    }
    Swag.assert(DestructuringDrops == 2 and DestructuringDropSum == 150)
}

#test
{
    DestructuringDrops   = 0
    DestructuringDropSum = 0
    DestructuringCopies  = 0
    scope
    {
        var owners = makeReorderedDestructuringOwners()
        {kept: owners.skipped, skipped: owners.kept} = owners
        Swag.assert(owners.kept.storage == 70 and owners.skipped.storage == 80)
        Swag.assert(owners.kept.isValid() and owners.skipped.isValid())
        Swag.assert(DestructuringCopies == 2 and DestructuringDrops == 2)
    }
    Swag.assert(DestructuringDrops == 4 and DestructuringDropSum == 300)
}
