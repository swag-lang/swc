// A local that every return reached in its scope returns is built directly in the storage the
// function returns through: returning it runs no hook at all. Any other shape keeps the local
// in its own storage, with ordinary local semantics.

var StorageCopies: s32
var StorageMoves:  s32
var StorageDrops:  s32
var StorageSeed:   s64 = 5
var StorageSink:   s64

// Wider than a register, so the result goes through the caller's storage.
struct StorageTracked
{
    value: s64
    pad:   [4] u64
}

impl StorageTracked
{
    mtd opPostCopy()
    {
        StorageCopies += 1
    }

    mtd opPostMove()
    {
        StorageMoves += 1
    }

    mtd opDrop()
    {
        StorageDrops += 1
    }
}

func resetStorageHooks()
{
    StorageCopies, StorageMoves, StorageDrops = 0
    StorageSink = 0
}

func expectStorageHooks(copies, moves, drops: s32)
{
    Swag.assert(StorageCopies == copies)
    Swag.assert(StorageMoves == moves)
    Swag.assert(StorageDrops == drops)
}

#[Swag.NoInline]
func storageBuilt(value: s64)->StorageTracked
{
    var result: StorageTracked
    result.value = value
    return result
}

#[Swag.NoInline]
func storageBranches(value: s64)->StorageTracked
{
    var result: #returntype
    result.value = value
    if value > 100 do
        return result
    result.value += 1
    return result
}

#[Swag.Inline]
func storageInlined(value: s64)->StorageTracked
{
    var result: StorageTracked
    result.value = value * 2
    return result
}

// The inline expansion builds its local in the caller's local, itself the caller's result.
#[Swag.NoInline]
func storageCallsInlined(value: s64)->StorageTracked
{
    let result = storageInlined(value)
    return result
}

// A returned expansion or call, expression body or not, builds where the result goes.
#[Swag.NoInline]
func storageReturnsInlined(value: s64)->StorageTracked
{
    return storageInlined(value)
}

#[Swag.NoInline]
func storageBodyInlined(value: s64)->StorageTracked => storageInlined(value)

#[Swag.NoInline]
func storageBodyCall(value: s64)->StorageTracked => storageBuilt(value)

// The expansion of an expression-bodied function builds its literal where the result goes.
#[Swag.Inline]
func storageLiteral(value: s64)->StorageTracked => {value: value + 1}

#[Swag.NoInline]
func storageBodyLiteral(value: s64)->StorageTracked => storageLiteral(value)

// Locals with disjoint scopes can both be the result.
#[Swag.NoInline]
func storageDisjoint(first: bool)->StorageTracked
{
    if first
    {
        var a: StorageTracked
        a.value = 1
        return a
    }

    var b: StorageTracked
    b.value = 2
    return b
}

// Another value returned while the local is in scope: that value is built apart, the local
// built in the result is released, and the value takes its place.
#[Swag.NoInline]
func storageReplaced(other: bool)->StorageTracked
{
    var result = storageBuilt(1)
    if other do
        return storageBuilt(2)
    return result
}

// A defer active at the return still sees the local after the value left it.
#[Swag.NoInline]
func storageDeferred(value: s64)->StorageTracked
{
    var result: StorageTracked
    result.value = value
    defer result.value = 0
    defer StorageSink = result.value
    return result
}

// A defer that only runs on failure never follows a return.
#[Swag.NoInline]
func storageFailDefer(succeed: bool)->StorageTracked fail
{
    var result: StorageTracked
    result.value = StorageSeed
    defer #fail StorageSink = result.value
    if not succeed do
        fail Swag.BaseError{"expected failure"}
    return result
}

// A defer that ends with its loop body is not active at the return after the loop.
#[Swag.NoInline]
func storageLoopDefer(count: s64)->StorageTracked
{
    var result: StorageTracked
    for i in count
    {
        defer result.value += 1
        StorageSink += i
    }

    return result
}

// A closure that captures the local by address borrows it while it runs, like '&local'.
func storageRun(fn: func||())
{
    fn()
}

#[Swag.NoInline]
func storageCaptured(value: s64)->StorageTracked
{
    var result: StorageTracked
    storageRun(func|&result, value|() { result.value = value })
    return result
}

// A return in a loop body injected by a visiting macro is still a return of this function,
// and the branches the macro does not compile are no other return.
struct StorageBag
{
    values: [3] s64 = [3, 6, 9]
}

impl StorageBag
{
    #[Swag.Macro]
    func(ptr: bool) opVisit(me, stmt: #code(item, index: u64))
    {
        #static if ptr
        {
            for idx in 3 do
                #inject(stmt, item = &me.values[idx], index = idx)
        }
        else
        {
            for idx in 3 do
                #inject(stmt, item = me.values[idx], index = idx)
        }
    }
}

#[Swag.NoInline]
func storageFirstAbove(limit: s64)->StorageTracked
{
    let bag = StorageBag{}
    var result: StorageTracked
    for v in bag
    {
        if v > limit
        {
            result.value = v
            return result
        }
    }

    return result
}

// A local of a loop body is built anew in the result storage at each iteration.
#[Swag.NoInline]
func storageLoopLocal(stop: s64)->StorageTracked
{
    for i in 10
    {
        var result: StorageTracked
        result.value = i
        if i == stop do
            return result
    }

    return storageBuilt(-1)
}

// Owns a release and states no copy: a defer that still observes it at the return leaves it
// moved from, never copied.
var StorageReleases: s32

struct StorageOwned
{
    id:  s64
    pad: [4] u64
}

impl StorageOwned
{
    mtd opDrop()
    {
        if id do
            StorageReleases += 1
    }
}

#[Swag.NoInline]
func storageObservedOwned()->StorageOwned
{
    var result: StorageOwned
    result.id = StorageSeed
    defer StorageSink = result.id
    return result
}

// '#move' asks for the same transfer of a copyable local.
#[Swag.NoInline]
func storageObservedMoved(value: s64)->StorageTracked
{
    var result: StorageTracked
    result.value = value
    defer StorageSink = result.value
    return #move result
}

// Bytes held inline are read through a pointer while another value is built.
struct StorageText
{
    buf: [16] u8
    len: u64
}

impl StorageText
{
    #[Swag.NoInline]
    mtd const view()->const [..] u8 => buf[0 until len]
}

#[Swag.NoInline]
func storageText(src: const [..] u8)->StorageText
{
    var r: #returntype
    for i in src.count do
        r.buf[i] = src[i]
    r.len = src.count
    return r
}

// The replacing value reads the local it replaces, which is released only afterwards.
#[Swag.NoInline]
func storageTrimmedReplaced(trim: bool)->StorageText
{
    var result: #returntype = storageText(" Satie ")
    if trim do
        return storageText(result.view()[1 until 6])
    return result
}

#[Swag.NoInline]
func storageLiteralReplaced(other: bool)->StorageTracked
{
    var result = storageBuilt(1)
    if other do
        return StorageTracked{value: 9}
    return result
}

#[Swag.NoInline]
func storageTrimmed()->StorageText
{
    var result = storageText(" Satie ")
    let p      = &result
    return storageText(p.view()[1 until 6])
}

#test
{
    resetStorageHooks()
    scope
    {
        let x = storageBuilt(StorageSeed)
        Swag.assert(x.value == 5)
    }
    expectStorageHooks(0, 0, 1)

    resetStorageHooks()
    scope
    {
        let x = storageBranches(StorageSeed)
        let y = storageBranches(StorageSeed + 200)
        Swag.assert(x.value == 6 and y.value == 205)
    }
    expectStorageHooks(0, 0, 2)

    resetStorageHooks()
    scope
    {
        let x = storageCallsInlined(StorageSeed)
        Swag.assert(x.value == 10)
    }
    expectStorageHooks(0, 0, 1)

    resetStorageHooks()
    scope
    {
        let x = storageReturnsInlined(StorageSeed)
        let y = storageBodyInlined(StorageSeed)
        let z = storageBodyCall(StorageSeed)
        let w = storageBodyLiteral(StorageSeed)
        Swag.assert(x.value == 10 and y.value == 10 and z.value == 5 and w.value == 6)
    }
    // The literal is built in the expansion's own result, then moves once into the slot.
    expectStorageHooks(0, 1, 4)

    resetStorageHooks()
    scope
    {
        let x = storageDisjoint(StorageSeed > 0)
        let y = storageDisjoint(StorageSeed < 0)
        Swag.assert(x.value == 1 and y.value == 2)
    }
    expectStorageHooks(0, 0, 2)
}

#test
{
    // The replaced local is released once; returned, it moves out instead.
    resetStorageHooks()
    scope
    {
        let x = storageReplaced(StorageSeed > 0)
        let y = storageReplaced(StorageSeed < 0)
        Swag.assert(x.value == 2 and y.value == 1)
    }
    expectStorageHooks(0, 1, 3)

    // The returned value is the one before the defers; they still see the local.
    resetStorageHooks()
    scope
    {
        let x = storageDeferred(StorageSeed)
        Swag.assert(x.value == 5)
        Swag.assert(StorageSink == 5)
    }
    expectStorageHooks(1, 0, 2)
}

#test
{
    resetStorageHooks()
    scope
    {
        let x = catch storageFailDefer(true)
        Swag.assert(x.value == 5)
        Swag.assert(StorageSink == 0)
    }
    expectStorageHooks(0, 0, 1)

    // On failure the local is released where it was built, and nothing is returned.
    resetStorageHooks()
    scope
    {
        let x = catch storageFailDefer(false)
        Swag.assert(x.value == 0)
        Swag.assert(StorageSink == 5)
    }
    Swag.assert(StorageCopies == 0 and StorageMoves == 0)

    resetStorageHooks()
    scope
    {
        let x = storageLoopDefer(StorageSeed)
        Swag.assert(x.value == 5)
        Swag.assert(StorageSink == 10)
    }
    expectStorageHooks(0, 0, 1)

    resetStorageHooks()
    scope
    {
        let x = storageFirstAbove(StorageSeed)
        let y = storageFirstAbove(StorageSeed + 10)
        Swag.assert(x.value == 6 and y.value == 0)
    }
    expectStorageHooks(0, 0, 2)

    resetStorageHooks()
    scope
    {
        let x = storageCaptured(StorageSeed)
        Swag.assert(x.value == 5)
    }
    expectStorageHooks(0, 0, 1)

    resetStorageHooks()
    scope
    {
        let x = storageLoopLocal(StorageSeed)
        Swag.assert(x.value == 5)
    }
    expectStorageHooks(0, 0, 6)
}

#test
{
    StorageReleases = 0
    StorageSink     = -1
    scope
    {
        let x = storageObservedOwned()
        Swag.assert(x.id == 5)
        Swag.assert(StorageSink == 0)
        Swag.assert(StorageReleases == 0)
    }
    Swag.assert(StorageReleases == 1)

    resetStorageHooks()
    StorageSink = -1
    scope
    {
        let x = storageObservedMoved(StorageSeed)
        Swag.assert(x.value == 5)
        Swag.assert(StorageSink == 0)
    }
    expectStorageHooks(0, 1, 2)
}

#test
{
    let trimmed = storageTrimmedReplaced(StorageSeed > 0)
    Swag.assert(trimmed.len == 5 and trimmed.buf[0] == 83 and trimmed.buf[4] == 101)
    let kept = storageTrimmedReplaced(StorageSeed < 0)
    Swag.assert(kept.len == 7 and kept.buf[0] == 32)

    resetStorageHooks()
    scope
    {
        let x = storageLiteralReplaced(StorageSeed > 0)
        let y = storageLiteralReplaced(StorageSeed < 0)
        Swag.assert(x.value == 9 and y.value == 1)
    }
    Swag.assert(StorageCopies == 0 and StorageDrops == 3)
}

#test
{
    let text = storageTrimmed()
    Swag.assert(text.len == 5 and text.buf[0] == 83 and text.buf[4] == 101)
}
