#global private

var LastInlineBufferTextDropAddr:       [*] void?
var LastInlineBufferTextDropBuffer:     [*] u8?
var ExpectedInlineBufferTextDropAddr:   [*] void?
var ExpectedInlineBufferTextDropBuffer: [*] u8?

struct SelfPointerValue
{
    storage: [8] u8
    buffer:  [*] u8?
}

impl SelfPointerValue
{
    mtd init(value: u8)
    {
        .storage[0] = value
        .storage[1] = 0
        .buffer     = cast([*] u8) &.storage[0]
    }

    mtd const first()->u8
    {
        return .buffer![]
    }

    mtd opPostCopy()
    {
        if .buffer do
            .buffer = cast([*] u8) &.storage[0]
    }

    mtd opDrop()
    {
        if .buffer do
            Swag.assert(.buffer == cast([*] u8) &.storage[0])
    }
}

struct(T) CopySlot
{
    value: T
}

impl CopySlot
{
    mtd assign(value: T)
    {
        .value = #nodrop value
    }
}

struct(T) EntryArray
{
    entries: [*] CopySlot'T?
}

impl EntryArray
{
    mtd addAt(index: u64, value: T)
    {
        let slots = .entries!
        slots[index].value = #nodrop value
    }
}

func maxU64(lhs: u64, rhs: u64)->u64
{
    if lhs >= rhs do
        return lhs
    return rhs
}

func minU64(lhs: u64, rhs: u64)->u64
{
    if lhs <= rhs do
        return lhs
    return rhs
}

struct InlineBufferText
{
    buffer:    [*] u8?
    length:    u64
    capacity:  u64
    allocator: IAllocator?
    padding:   [16] u8
}

impl InlineBufferText
{
    #[Implicit]
    mtd opSet(value: string)
    {
        let newCapacity = value.count + 1
        .length = newCapacity - 1
        .grow(newCapacity)
        let buf = .buffer!
        Swag.memcpy(buf, value.buffer, .length)
        buf[.length] = 0
    }

    mtd grow(wantedCapacity: u64)
    {
        if wantedCapacity <= .capacity do
            return
        let newCapacity = maxU64(.capacity * 2, wantedCapacity)
        .reserve(newCapacity)
    }

    mtd reserve(newCapacity: u64)
    {
        .length = minU64(.length, newCapacity)
        if .allocator == null do
            .allocator = Swag.getContext().allocator

        if newCapacity <= 16
        {
            .capacity = 16
            .buffer   = cast([*] u8) &.padding[0]
            return
        }

        Swag.assert(false)
    }

    mtd const asString()->string
    {
        return Swag.makeString(.buffer!, .length)
    }

    mtd opPostCopy()
    {
        if .buffer do
            .buffer = cast([*] u8) &.padding[0]
    }

    mtd opDrop()
    {
        let dropAddr = cast([*] void) me
        LastInlineBufferTextDropAddr = dropAddr
        if ExpectedInlineBufferTextDropAddr
        {
            Swag.assert(dropAddr == ExpectedInlineBufferTextDropAddr)
            LastInlineBufferTextDropBuffer = .buffer
            if ExpectedInlineBufferTextDropBuffer do
                Swag.assert(.buffer == ExpectedInlineBufferTextDropBuffer)
        }
    }
}

struct(K, V) HashLikeEntry
{
    hash:  u32
    key:   K
    value: V
}

struct(K, V) HashLikeTable
{
    entries:  [*] HashLikeEntry'(K, V)?
    capacity: u64
}

impl HashLikeTable
{
    mtd add(key: K, value: V)
    {
        let slots = .entries!
        slots[0].key   = #nodrop key
        slots[0].value = #nodrop value
        slots[0].hash  = 2
    }

    mtd valueAddr(index: u64)->[*] void
    {
        let slots = .entries!
        return cast([*] void) &slots[index].value
    }

    mtd free()
    {
        let slots = .entries!
        for i in .capacity where slots[i].hash >= 1 do
            Swag.drop(&slots[i].value)
        testFree(slots)
        .entries  = null
        .capacity = 0
    }
}

func makeInlineBufferText(value: string)->InlineBufferText
{
    var result: InlineBufferText
    result = value
    return result
}

func dropInlineBufferText(ptr: *InlineBufferText)
{
    Swag.drop(ptr)
}

#test
{
    var slot: CopySlot'SelfPointerValue
    var src:  SelfPointerValue
    src.init(7)

    slot.assign(src)

    Swag.assert(slot.value.first() == 7)
    Swag.assert(slot.value.buffer == cast([*] u8) &slot.value.storage[0])
}

#test
{
    let entries = cast([*] CopySlot'SelfPointerValue) testAlloc(#sizeof(CopySlot'SelfPointerValue))!
    defer testFree(entries)
    Swag.memset(entries, 0, #sizeof(CopySlot'SelfPointerValue))

    var table: EntryArray'SelfPointerValue
    table.entries = entries

    var src: SelfPointerValue
    src.init(9)

    table.addAt(0, src)

    Swag.assert(table.entries[0].value.first() == 9)
    Swag.assert(table.entries[0].value.buffer == cast([*] u8) &table.entries[0].value.storage[0])
    Swag.drop(&table.entries[0].value)
}

#test
{
    let entries = cast([*] CopySlot'InlineBufferText) testAlloc(#sizeof(CopySlot'InlineBufferText))!
    defer testFree(entries)
    Swag.memset(entries, 0, #sizeof(CopySlot'InlineBufferText))

    var table: EntryArray'InlineBufferText
    table.entries = entries

    table.addAt(0, makeInlineBufferText("swag"))

    Swag.assert(table.entries[0].value.asString() == "swag")
    Swag.assert(table.entries[0].value.buffer == cast([*] u8) &table.entries[0].value.padding[0])
    Swag.drop(&table.entries[0].value)
}

#test
{
    let entries = cast([*] HashLikeEntry'(string, InlineBufferText)) (testAlloc(#sizeof(HashLikeEntry'(string, InlineBufferText))))!
    Swag.memset(entries, 0, #sizeof(HashLikeEntry'(string, InlineBufferText)))

    var table: HashLikeTable'(string, InlineBufferText)
    table.entries  = entries
    table.capacity = 1

    table.add("alpha", makeInlineBufferText("one"))
    let expectedDropAddr   = cast([*] void) &table.entries[0].value
    let expectedDropBuffer = cast([*] u8) &table.entries[0].value.padding[0]
    Swag.assert(table.valueAddr(0) == expectedDropAddr)

    Swag.assert(table.entries[0].hash == 2)
    Swag.assert(table.entries[0].key == "alpha")
    Swag.assert(table.entries[0].value.asString() == "one")
    Swag.assert(table.entries[0].value.buffer == expectedDropBuffer)
    LastInlineBufferTextDropAddr   = null
    LastInlineBufferTextDropBuffer = null
    testFree(entries)
}

#test
{
    let entries = cast([*] HashLikeEntry'(s32, InlineBufferText)) (testAlloc(#sizeof(HashLikeEntry'(s32, InlineBufferText))))!
    Swag.memset(entries, 0, #sizeof(HashLikeEntry'(s32, InlineBufferText)))

    var table: HashLikeTable'(s32, InlineBufferText)
    table.entries  = entries
    table.capacity = 1

    table.add(7, "one")
    let expectedDropAddr   = table.valueAddr(0)
    let expectedDropBuffer = cast([*] u8) &table.entries[0].value.padding[0]
    LastInlineBufferTextDropAddr       = null
    LastInlineBufferTextDropBuffer     = null
    ExpectedInlineBufferTextDropAddr   = expectedDropAddr
    ExpectedInlineBufferTextDropBuffer = expectedDropBuffer
    table.free()
    Swag.assert(LastInlineBufferTextDropAddr == expectedDropAddr)
    Swag.assert(LastInlineBufferTextDropBuffer == expectedDropBuffer)
}

#test
{
    let entries = cast([*] HashLikeEntry'(string, InlineBufferText)) (testAlloc(#sizeof(HashLikeEntry'(string, InlineBufferText))))!
    Swag.memset(entries, 0, #sizeof(HashLikeEntry'(string, InlineBufferText)))

    var table: HashLikeTable'(string, InlineBufferText)
    table.entries  = entries
    table.capacity = 1

    table.add("alpha", "one")
    let expectedDropBuffer = cast([*] u8) &table.entries[0].value.padding[0]

    LastInlineBufferTextDropAddr       = null
    LastInlineBufferTextDropBuffer     = null
    ExpectedInlineBufferTextDropAddr   = table.valueAddr(0)
    ExpectedInlineBufferTextDropBuffer = expectedDropBuffer
    table.free()
    Swag.assert(LastInlineBufferTextDropAddr == ExpectedInlineBufferTextDropAddr)
    Swag.assert(LastInlineBufferTextDropBuffer == expectedDropBuffer)
}
