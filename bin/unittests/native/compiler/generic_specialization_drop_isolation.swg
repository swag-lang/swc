#global private

var LeakLastDropAddr: [*] void
var LeakLastDropSelf: [*] u8
var LeakLastDropTag:  s32
var LeakFirstDropAddr: [*] void
var LeakFirstDropTag:  s32
var LeakSecondDropAddr: [*] void
var LeakSecondDropTag:  s32

var LeakExpectedDropAddr: [*] void
var LeakExpectedDropSelf: [*] u8
var LeakExpectedDropTag:  s32
var LeakExpectDrop:       bool
var LeakDropCount:        s32

struct LeakWideKey
{
    left:  u64
    right: u16
    pad:   [3] u8
}

func makeLeakWideKey(left: u64, right: u16)->LeakWideKey
{
    return {left: left, right: right, pad: [1, 2, 3]}
}

func leakResetDropProbe()
{
    LeakLastDropAddr = null
    LeakLastDropSelf = null
    LeakLastDropTag = 0
    LeakFirstDropAddr = null
    LeakFirstDropTag = 0
    LeakSecondDropAddr = null
    LeakSecondDropTag = 0
    LeakExpectedDropAddr = null
    LeakExpectedDropSelf = null
    LeakExpectedDropTag = 0
    LeakExpectDrop = false
    LeakDropCount = 0
}

// The probe intentionally publishes caller-local addresses into the global drop
// registry (disarmed before the owners die): opt out of the stored-argument check.
#[Swag.Sanity(.Lifecycle, false)]
func leakArmExpectedDrop(addr: [*] void, self: [*] u8, tag: s32)
{
    LeakLastDropAddr = null
    LeakLastDropSelf = null
    LeakLastDropTag = 0
    LeakExpectedDropAddr = addr
    LeakExpectedDropSelf = self
    LeakExpectedDropTag = tag
    LeakExpectDrop = true
}

func leakDisarmExpectedDrop()
{
    LeakExpectDrop = false
    LeakExpectedDropAddr = null
    LeakExpectedDropSelf = null
    LeakExpectedDropTag = 0
}

struct LeakTrackedValue
{
    tag:     s32
    storage: [16] u8
    self:    [*] u8
}

impl LeakTrackedValue
{
    #[Implicit]
    mtd opSet(tag: s32)
    {
        .tag = tag
        .storage[0] = cast(u8) tag
        .storage[1] = cast(u8) (tag + 1)
        .self = cast([*] u8) &.storage[0]
    }

    mtd opPostCopy()
    {
        if .self do
            .self = cast([*] u8) &.storage[0]
    }

    mtd const marker()->s32
    {
        return .tag + cast(s32) dref .self + cast(s32) .storage[1]
    }

    mtd opDrop()
    {
        let dropAddr = cast([*] void) &me
        LeakDropCount += 1
        if LeakDropCount == 1
        {
            LeakFirstDropAddr = dropAddr
            LeakFirstDropTag = .tag
        }
        if LeakDropCount == 2
        {
            LeakSecondDropAddr = dropAddr
            LeakSecondDropTag = .tag
        }
        LeakLastDropAddr = dropAddr
        LeakLastDropSelf = .self
        LeakLastDropTag = .tag

        if LeakExpectDrop
        {
            @assert(dropAddr == LeakExpectedDropAddr)
            @assert(.self == LeakExpectedDropSelf)
            @assert(.tag == LeakExpectedDropTag)
            @assert(dref .self == cast(u8) .tag)
        }
    }
}

struct(K, V) LeakEntry
{
    head:  u32
    key:   K
    value: V
    tail:  u16
}

struct(K, V) LeakTable
{
    entries: [2] LeakEntry'(K, V)
    live:    [2] bool
}

func(K, V) leakDropEntryValue(entry: *LeakEntry'(K, V))
{
    @drop(&entry.value)
}

func(V) leakDropValuePtr(ptr: *V)
{
    @drop(ptr)
}

impl LeakTable
{
    #[Swag.NoInline]
    mtd put(index: s32, key: K, value: V)
    {
        .entries[index].head = cast(u32) index + 1
        .entries[index].key = #nodrop key
        .entries[index].value = #nodrop value
        .entries[index].tail = cast(u16) index + 10
        .live[index] = true
    }

    #[Swag.NoInline]
    mtd const valueAddr(index: s32)->[*] void
    {
        return cast([*] void) &.entries[index].value
    }

    #[Swag.NoInline]
    mtd valuePtr(index: s32)->*V
    {
        return &.entries[index].value
    }

    #[Swag.NoInline]
    mtd entryPtr(index: s32)->*LeakEntry'(K, V)
    {
        return &.entries[index]
    }

    #[Swag.NoInline]
    mtd dropAt(index: s32)
    {
        @drop(&.entries[index].value)
        .live[index] = false
    }

    #[Swag.NoInline]
    mtd dropViaValuePtr(index: s32)
    {
        let ptr = .valuePtr(index)
        @drop(ptr)
        .live[index] = false
    }

    #[Swag.NoInline]
    mtd dropViaEntryPtr(index: s32)
    {
        let entry = .entryPtr(index)
        @drop(&entry.value)
        .live[index] = false
    }

    #[Swag.NoInline]
    mtd dropViaEntryHelper(index: s32)
    {
        leakDropEntryValue(&.entries[index])
        .live[index] = false
    }

    #[Swag.NoInline]
    mtd dropViaValueHelper(index: s32)
    {
        leakDropValuePtr(&.entries[index].value)
        .live[index] = false
    }

    #[Swag.NoInline]
    mtd dropAllLive()
    {
        if .live[0] do
            @drop(&.entries[0].value)
        if .live[1] do
            @drop(&.entries[1].value)
        .live = [false, false]
    }
}

struct(K, V) LeakBox
{
    table: LeakTable'(K, V)
}

impl LeakBox
{
    #[Swag.NoInline]
    mtd put(index: s32, key: K, value: V)
    {
        .table.put(index, key, value)
    }

    #[Swag.NoInline]
    mtd const valueAddr(index: s32)->[*] void
    {
        return cast([*] void) &.table.entries[index].value
    }

    #[Swag.NoInline]
    mtd dropAt(index: s32)
    {
        @drop(&.table.entries[index].value)
        .table.live[index] = false
    }
}

struct(K, V) LeakGrid
{
    tables: [2] LeakTable'(K, V)
}

impl LeakGrid
{
    #[Swag.NoInline]
    mtd put(tableIndex: s32, entryIndex: s32, key: K, value: V)
    {
        .tables[tableIndex].put(entryIndex, key, value)
    }

    #[Swag.NoInline]
    mtd const valueAddr(tableIndex: s32, entryIndex: s32)->[*] void
    {
        return cast([*] void) &.tables[tableIndex].entries[entryIndex].value
    }

    #[Swag.NoInline]
    mtd dropAt(tableIndex: s32, entryIndex: s32)
    {
        @drop(&.tables[tableIndex].entries[entryIndex].value)
        .tables[tableIndex].live[entryIndex] = false
    }
}

#if true
{
    // Reproducer: interleaving `LeakTable` specializations with different key layouts can make the
    // direct `@drop(&.entries[index].value)` path target the wrong address in a later specialization.
    #test
    {
        leakResetDropProbe()

        var byString: LeakTable'(string, LeakTrackedValue)
        var byInt:    LeakTable'(s32, LeakTrackedValue)
        var byWide:   LeakTable'(LeakWideKey, LeakTrackedValue)

        byString.put(0, "alpha", 11)
        byInt.put(0, 7, 21)
        byWide.put(0, makeLeakWideKey(3, 4), 31)

        byWide.put(1, makeLeakWideKey(5, 6), 32)
        byString.put(1, "beta", 12)
        byInt.put(1, 8, 22)

        @assert(byString.entries[1].value.marker() == 37)
        @assert(byInt.entries[1].value.marker() == 67)
        @assert(byWide.entries[0].value.marker() == 94)

        leakArmExpectedDrop(byInt.valueAddr(1), cast([*] u8) &byInt.entries[1].value.storage[0], 22)
        byInt.dropAt(1)
        leakDisarmExpectedDrop()
        @assert(LeakDropCount == 1)
        @assert(LeakLastDropAddr == byInt.valueAddr(1))
        @assert(LeakLastDropSelf == cast([*] u8) &byInt.entries[1].value.storage[0])
        @assert(LeakLastDropTag == 22)

        leakArmExpectedDrop(byString.valueAddr(0), cast([*] u8) &byString.entries[0].value.storage[0], 11)
        byString.dropAt(0)
        leakDisarmExpectedDrop()
        @assert(LeakDropCount == 2)
        @assert(LeakLastDropAddr == byString.valueAddr(0))
        @assert(LeakLastDropSelf == cast([*] u8) &byString.entries[0].value.storage[0])
        @assert(LeakLastDropTag == 11)

        leakArmExpectedDrop(byWide.valueAddr(1), cast([*] u8) &byWide.entries[1].value.storage[0], 32)
        byWide.dropAt(1)
        leakDisarmExpectedDrop()
        @assert(LeakDropCount == 3)
        @assert(LeakLastDropAddr == byWide.valueAddr(1))
        @assert(LeakLastDropSelf == cast([*] u8) &byWide.entries[1].value.storage[0])
        @assert(LeakLastDropTag == 32)
    }
}

#if true
{
    // Reproducer: the address leak is not limited to the direct member path.
    // Pointer-return and helper-mediated drops can also target the wrong `value` slot after
    // warming up sibling specializations of the same generic root.
    #test
    {
        leakResetDropProbe()

        var byString: LeakTable'(string, LeakTrackedValue)
        var byInt:    LeakTable'(s32, LeakTrackedValue)
        var byWide:   LeakTable'(LeakWideKey, LeakTrackedValue)

        byInt.put(0, 1, 41)
        byWide.put(0, makeLeakWideKey(8, 9), 51)
        byString.put(0, "gamma", 61)

        byString.put(1, "delta", 62)
        byInt.put(1, 2, 42)
        byWide.put(1, makeLeakWideKey(10, 11), 52)

        leakArmExpectedDrop(byWide.valueAddr(0), cast([*] u8) &byWide.entries[0].value.storage[0], 51)
        byWide.dropViaValuePtr(0)
        leakDisarmExpectedDrop()
        @assert(LeakLastDropAddr == byWide.valueAddr(0))
        @assert(LeakLastDropTag == 51)

        leakArmExpectedDrop(byString.valueAddr(1), cast([*] u8) &byString.entries[1].value.storage[0], 62)
        byString.dropViaEntryPtr(1)
        leakDisarmExpectedDrop()
        @assert(LeakLastDropAddr == byString.valueAddr(1))
        @assert(LeakLastDropTag == 62)

        leakArmExpectedDrop(byInt.valueAddr(0), cast([*] u8) &byInt.entries[0].value.storage[0], 41)
        byInt.dropViaEntryHelper(0)
        leakDisarmExpectedDrop()
        @assert(LeakLastDropAddr == byInt.valueAddr(0))
        @assert(LeakLastDropTag == 41)

        leakArmExpectedDrop(byInt.valueAddr(1), cast([*] u8) &byInt.entries[1].value.storage[0], 42)
        byInt.dropViaValueHelper(1)
        leakDisarmExpectedDrop()
        @assert(LeakLastDropAddr == byInt.valueAddr(1))
        @assert(LeakLastDropTag == 42)
    }
}

#if true
{
    // Reproducer: the leak survives one more level of member chaining through another generic
    // owner (`LeakBox.table.entries[index].value`).
    #test
    {
        leakResetDropProbe()

        var boxedString: LeakBox'(string, LeakTrackedValue)
        var boxedInt:    LeakBox'(s32, LeakTrackedValue)

        boxedString.put(0, "left", 71)
        boxedInt.put(0, 4, 81)
        boxedString.put(1, "right", 72)
        boxedInt.put(1, 5, 82)

        @assert(boxedString.table.entries[0].value.marker() == 214)
        @assert(boxedInt.table.entries[1].value.marker() == 247)

        leakArmExpectedDrop(boxedInt.valueAddr(0), cast([*] u8) &boxedInt.table.entries[0].value.storage[0], 81)
        boxedInt.dropAt(0)
        leakDisarmExpectedDrop()
        @assert(LeakLastDropAddr == boxedInt.valueAddr(0))
        @assert(LeakLastDropTag == 81)

        leakArmExpectedDrop(boxedString.valueAddr(1), cast([*] u8) &boxedString.table.entries[1].value.storage[0], 72)
        boxedString.dropAt(1)
        leakDisarmExpectedDrop()
        @assert(LeakLastDropAddr == boxedString.valueAddr(1))
        @assert(LeakLastDropTag == 72)
    }
}

#if true
{
    // Reproducer: the leak also survives a `tableIndex/entryIndex` access chain.
    #test
    {
        leakResetDropProbe()

        var gridString: LeakGrid'(string, LeakTrackedValue)
        var gridWide:   LeakGrid'(LeakWideKey, LeakTrackedValue)

        gridString.put(0, 0, "north", 91)
        gridWide.put(0, 0, makeLeakWideKey(12, 13), 101)
        gridString.put(1, 1, "south", 92)
        gridWide.put(1, 1, makeLeakWideKey(14, 15), 102)

        leakArmExpectedDrop(gridWide.valueAddr(1, 1), cast([*] u8) &gridWide.tables[1].entries[1].value.storage[0], 102)
        gridWide.dropAt(1, 1)
        leakDisarmExpectedDrop()
        @assert(LeakLastDropAddr == gridWide.valueAddr(1, 1))
        @assert(LeakLastDropTag == 102)

        leakArmExpectedDrop(gridString.valueAddr(0, 0), cast([*] u8) &gridString.tables[0].entries[0].value.storage[0], 91)
        gridString.dropAt(0, 0)
        leakDisarmExpectedDrop()
        @assert(LeakLastDropAddr == gridString.valueAddr(0, 0))
        @assert(LeakLastDropTag == 91)
    }
}

#if true
{
    // Reproducer: even without extra nesting or helper indirection, dropping all live entries after
    // warming up another specialization can still pick the wrong `value` address.
    #test
    {
        leakResetDropProbe()

        var byString: LeakTable'(string, LeakTrackedValue)
        var byInt:    LeakTable'(s32, LeakTrackedValue)

        byString.put(0, "warmup", 111)
        byInt.put(0, 6, 121)
        byString.put(1, "tail", 112)
        byInt.put(1, 7, 122)

        byInt.dropAllLive()
        @assert(LeakDropCount == 2)
        @assert(LeakFirstDropAddr == byInt.valueAddr(0))
        @assert(LeakFirstDropTag == 121)
        @assert(LeakSecondDropAddr == byInt.valueAddr(1))
        @assert(LeakSecondDropTag == 122)
        @assert(LeakLastDropAddr == byInt.valueAddr(1))
        @assert(LeakLastDropTag == 122)

        leakResetDropProbe()
        byString.dropAllLive()
        @assert(LeakDropCount == 2)
        @assert(LeakFirstDropAddr == byString.valueAddr(0))
        @assert(LeakFirstDropTag == 111)
        @assert(LeakSecondDropAddr == byString.valueAddr(1))
        @assert(LeakSecondDropTag == 112)
        @assert(LeakLastDropAddr == byString.valueAddr(1))
        @assert(LeakLastDropTag == 112)
    }
}
