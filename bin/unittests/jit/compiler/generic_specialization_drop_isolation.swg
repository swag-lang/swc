#global private

// The registry records WHICH slot was dropped, never a pointer it can follow: every use
// below is an equality test. Addresses are therefore kept as plain identities, so the
// probe does not publish a caller frame address into a global that outlives the frame.
var LeakLastDropAddr:   u64
var LeakLastDropSelf:   u64
var LeakLastDropTag:    s32
var LeakFirstDropAddr:  u64
var LeakFirstDropTag:   s32
var LeakSecondDropAddr: u64
var LeakSecondDropTag:  s32

var LeakExpectedDropAddr: u64
var LeakExpectedDropSelf: u64
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
    LeakLastDropAddr     = 0
    LeakLastDropSelf     = 0
    LeakLastDropTag      = 0
    LeakFirstDropAddr    = 0
    LeakFirstDropTag     = 0
    LeakSecondDropAddr   = 0
    LeakSecondDropTag    = 0
    LeakExpectedDropAddr = 0
    LeakExpectedDropSelf = 0
    LeakExpectedDropTag  = 0
    LeakExpectDrop       = false
    LeakDropCount        = 0
}

func leakArmExpectedDrop(addr: [*] void, self: [*] u8, tag: s32)
{
    LeakLastDropAddr     = 0
    LeakLastDropSelf     = 0
    LeakLastDropTag      = 0
    LeakExpectedDropAddr = cast(u64) addr
    LeakExpectedDropSelf = cast(u64) self
    LeakExpectedDropTag  = tag
    LeakExpectDrop       = true
}

func leakDisarmExpectedDrop()
{
    LeakExpectDrop       = false
    LeakExpectedDropAddr = 0
    LeakExpectedDropSelf = 0
    LeakExpectedDropTag  = 0
}

struct LeakTrackedValue
{
    tag:     s32
    storage: [16] u8
    self:    #null [*] u8
}

impl LeakTrackedValue
{
    #[Implicit]
    mtd opSet(tag: s32)
    {
        .tag        = tag
        .storage[0] = cast(u8) tag
        .storage[1] = cast(u8) (tag + 1)
        .self       = cast([*] u8) &.storage[0]
    }

    mtd opPostCopy()
    {
        if .self do
            .self = cast([*] u8) &.storage[0]
    }

    mtd const marker()->s32
    {
        return .tag + cast(s32) .self![] + cast(s32) .storage[1]
    }

    mtd opDrop()
    {
        let dropAddr = cast(u64) me
        LeakDropCount += 1
        if LeakDropCount == 1
        {
            LeakFirstDropAddr = dropAddr
            LeakFirstDropTag  = .tag
        }
        if LeakDropCount == 2
        {
            LeakSecondDropAddr = dropAddr
            LeakSecondDropTag  = .tag
        }
        LeakLastDropAddr = dropAddr
        LeakLastDropSelf = cast(u64) .self
        LeakLastDropTag  = .tag

        if LeakExpectDrop
        {
            Swag.assert(dropAddr == LeakExpectedDropAddr)
            Swag.assert(cast(u64) .self == LeakExpectedDropSelf)
            Swag.assert(.tag == LeakExpectedDropTag)
            Swag.assert(.self![] == cast(u8) .tag)
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
    Swag.drop(&entry.value)
}

func(V) leakDropValuePtr(ptr: *V)
{
    Swag.drop(ptr)
}

impl LeakTable
{
    #[Swag.NoInline]
    mtd put(index: s32, key: K, value: V)
    {
        .entries[index].head  = cast(u32) index + 1
        .entries[index].key   = #nodrop key
        .entries[index].value = #nodrop value
        .entries[index].tail  = cast(u16) index + 10
        .live[index]          = true
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
        Swag.drop(&.entries[index].value)
        .live[index] = false
    }

    #[Swag.NoInline]
    mtd dropViaValuePtr(index: s32)
    {
        let ptr = .valuePtr(index)
        Swag.drop(ptr)
        .live[index] = false
    }

    #[Swag.NoInline]
    mtd dropViaEntryPtr(index: s32)
    {
        let entry = .entryPtr(index)
        Swag.drop(&entry.value)
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
            Swag.drop(&.entries[0].value)
        if .live[1] do
            Swag.drop(&.entries[1].value)
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
        Swag.drop(&.table.entries[index].value)
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
        Swag.drop(&.tables[tableIndex].entries[entryIndex].value)
        .tables[tableIndex].live[entryIndex] = false
    }
}

#static if true
{
    // Reproducer: interleaving `LeakTable` specializations with different key layouts can make the
    // direct `Swag.drop(&.entries[index].value)` path target the wrong address in a later specialization.
    #test
    {
        leakResetDropProbe()

        var byString: LeakTable'(string, LeakTrackedValue) = undefined
        var byInt:    LeakTable'(s32, LeakTrackedValue)
        var byWide:   LeakTable'(LeakWideKey, LeakTrackedValue)

        byString.put(0, "alpha", 11)
        byInt.put(0, 7, 21)
        byWide.put(0, makeLeakWideKey(3, 4), 31)

        byWide.put(1, makeLeakWideKey(5, 6), 32)
        byString.put(1, "beta", 12)
        byInt.put(1, 8, 22)

        Swag.assert(byString.entries[1].value.marker() == 37)
        Swag.assert(byInt.entries[1].value.marker() == 67)
        Swag.assert(byWide.entries[0].value.marker() == 94)

        leakArmExpectedDrop(byInt.valueAddr(1), cast([*] u8) &byInt.entries[1].value.storage[0], 22)
        byInt.dropAt(1)
        leakDisarmExpectedDrop()
        Swag.assert(LeakDropCount == 1)
        Swag.assert(LeakLastDropAddr == cast(u64) byInt.valueAddr(1))
        Swag.assert(LeakLastDropSelf == cast(u64) &byInt.entries[1].value.storage[0])
        Swag.assert(LeakLastDropTag == 22)

        leakArmExpectedDrop(byString.valueAddr(0), cast([*] u8) &byString.entries[0].value.storage[0], 11)
        byString.dropAt(0)
        leakDisarmExpectedDrop()
        Swag.assert(LeakDropCount == 2)
        Swag.assert(LeakLastDropAddr == cast(u64) byString.valueAddr(0))
        Swag.assert(LeakLastDropSelf == cast(u64) &byString.entries[0].value.storage[0])
        Swag.assert(LeakLastDropTag == 11)

        leakArmExpectedDrop(byWide.valueAddr(1), cast([*] u8) &byWide.entries[1].value.storage[0], 32)
        byWide.dropAt(1)
        leakDisarmExpectedDrop()
        Swag.assert(LeakDropCount == 3)
        Swag.assert(LeakLastDropAddr == cast(u64) byWide.valueAddr(1))
        Swag.assert(LeakLastDropSelf == cast(u64) &byWide.entries[1].value.storage[0])
        Swag.assert(LeakLastDropTag == 32)
    }
}

#static if true
{
    // Reproducer: the address leak is not limited to the direct member path.
    // Pointer-return and helper-mediated drops can also target the wrong `value` slot after
    // warming up sibling specializations of the same generic root.
    #test
    {
        leakResetDropProbe()

        var byString: LeakTable'(string, LeakTrackedValue) = undefined
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
        Swag.assert(LeakLastDropAddr == cast(u64) byWide.valueAddr(0))
        Swag.assert(LeakLastDropTag == 51)

        leakArmExpectedDrop(byString.valueAddr(1), cast([*] u8) &byString.entries[1].value.storage[0], 62)
        byString.dropViaEntryPtr(1)
        leakDisarmExpectedDrop()
        Swag.assert(LeakLastDropAddr == cast(u64) byString.valueAddr(1))
        Swag.assert(LeakLastDropTag == 62)

        leakArmExpectedDrop(byInt.valueAddr(0), cast([*] u8) &byInt.entries[0].value.storage[0], 41)
        byInt.dropViaEntryHelper(0)
        leakDisarmExpectedDrop()
        Swag.assert(LeakLastDropAddr == cast(u64) byInt.valueAddr(0))
        Swag.assert(LeakLastDropTag == 41)

        leakArmExpectedDrop(byInt.valueAddr(1), cast([*] u8) &byInt.entries[1].value.storage[0], 42)
        byInt.dropViaValueHelper(1)
        leakDisarmExpectedDrop()
        Swag.assert(LeakLastDropAddr == cast(u64) byInt.valueAddr(1))
        Swag.assert(LeakLastDropTag == 42)
    }
}

#static if true
{
    // Reproducer: the leak survives one more level of member chaining through another generic
    // owner (`LeakBox.table.entries[index].value`).
    #test
    {
        leakResetDropProbe()

        var boxedString: LeakBox'(string, LeakTrackedValue) = undefined
        var boxedInt:    LeakBox'(s32, LeakTrackedValue)

        boxedString.put(0, "left", 71)
        boxedInt.put(0, 4, 81)
        boxedString.put(1, "right", 72)
        boxedInt.put(1, 5, 82)

        Swag.assert(boxedString.table.entries[0].value.marker() == 214)
        Swag.assert(boxedInt.table.entries[1].value.marker() == 247)

        leakArmExpectedDrop(boxedInt.valueAddr(0), cast([*] u8) &boxedInt.table.entries[0].value.storage[0], 81)
        boxedInt.dropAt(0)
        leakDisarmExpectedDrop()
        Swag.assert(LeakLastDropAddr == cast(u64) boxedInt.valueAddr(0))
        Swag.assert(LeakLastDropTag == 81)

        leakArmExpectedDrop(boxedString.valueAddr(1), cast([*] u8) &boxedString.table.entries[1].value.storage[0], 72)
        boxedString.dropAt(1)
        leakDisarmExpectedDrop()
        Swag.assert(LeakLastDropAddr == cast(u64) boxedString.valueAddr(1))
        Swag.assert(LeakLastDropTag == 72)
    }
}

#static if true
{
    // Reproducer: the leak also survives a `tableIndex/entryIndex` access chain.
    #test
    {
        leakResetDropProbe()

        var gridString: LeakGrid'(string, LeakTrackedValue) = undefined
        var gridWide:   LeakGrid'(LeakWideKey, LeakTrackedValue)

        gridString.put(0, 0, "north", 91)
        gridWide.put(0, 0, makeLeakWideKey(12, 13), 101)
        gridString.put(1, 1, "south", 92)
        gridWide.put(1, 1, makeLeakWideKey(14, 15), 102)

        leakArmExpectedDrop(gridWide.valueAddr(1, 1), cast([*] u8) &gridWide.tables[1].entries[1].value.storage[0], 102)
        gridWide.dropAt(1, 1)
        leakDisarmExpectedDrop()
        Swag.assert(LeakLastDropAddr == cast(u64) gridWide.valueAddr(1, 1))
        Swag.assert(LeakLastDropTag == 102)

        leakArmExpectedDrop(gridString.valueAddr(0, 0), cast([*] u8) &gridString.tables[0].entries[0].value.storage[0], 91)
        gridString.dropAt(0, 0)
        leakDisarmExpectedDrop()
        Swag.assert(LeakLastDropAddr == cast(u64) gridString.valueAddr(0, 0))
        Swag.assert(LeakLastDropTag == 91)
    }
}

#static if true
{
    // Reproducer: even without extra nesting or helper indirection, dropping all live entries after
    // warming up another specialization can still pick the wrong `value` address.
    #test
    {
        leakResetDropProbe()

        var byString: LeakTable'(string, LeakTrackedValue) = undefined
        var byInt:    LeakTable'(s32, LeakTrackedValue)

        byString.put(0, "warmup", 111)
        byInt.put(0, 6, 121)
        byString.put(1, "tail", 112)
        byInt.put(1, 7, 122)

        byInt.dropAllLive()
        Swag.assert(LeakDropCount == 2)
        Swag.assert(LeakFirstDropAddr == cast(u64) byInt.valueAddr(0))
        Swag.assert(LeakFirstDropTag == 121)
        Swag.assert(LeakSecondDropAddr == cast(u64) byInt.valueAddr(1))
        Swag.assert(LeakSecondDropTag == 122)
        Swag.assert(LeakLastDropAddr == cast(u64) byInt.valueAddr(1))
        Swag.assert(LeakLastDropTag == 122)

        leakResetDropProbe()
        byString.dropAllLive()
        Swag.assert(LeakDropCount == 2)
        Swag.assert(LeakFirstDropAddr == cast(u64) byString.valueAddr(0))
        Swag.assert(LeakFirstDropTag == 111)
        Swag.assert(LeakSecondDropAddr == cast(u64) byString.valueAddr(1))
        Swag.assert(LeakSecondDropTag == 112)
        Swag.assert(LeakLastDropAddr == cast(u64) byString.valueAddr(1))
        Swag.assert(LeakLastDropTag == 112)
    }
}
