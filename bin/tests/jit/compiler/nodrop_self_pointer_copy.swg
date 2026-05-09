#global fileprivate

var LastInlineBufferTextDropAddr: [*] void

struct SelfPointerValue
{
    storage: [8] u8
    buffer:  [*] u8
}

impl SelfPointerValue
{
    mtd init(value: u8)
    {
        .storage[0] = value
        .storage[1] = 0
        .buffer = cast([*] u8) &.storage[0]
    }

    mtd const first()->u8
    {
        return dref .buffer
    }

    mtd opPostCopy()
    {
        if .buffer do
            .buffer = cast([*] u8) &.storage[0]
    }

    mtd opDrop()
    {
        if .buffer do
            @assert(.buffer == cast([*] u8) &.storage[0])
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
    entries: [*] CopySlot'T
}

impl EntryArray
{
    mtd addAt(index: u64, value: T)
    {
        .entries[index].value = #nodrop value
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
    buffer:    [*] u8
    length:    u64
    capacity:  u64
    allocator: IAllocator
    padding:   [16] u8
}

impl InlineBufferText
{
    #[Implicit]
    mtd opSet(value: string)
    {
        let newCapacity = @countof(value) + 1
        .length = newCapacity - 1
        .grow(newCapacity)
        @memcpy(.buffer, @dataof(value), .length)
        .buffer[.length] = 0
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
            .allocator = @getcontext().allocator

        if newCapacity <= 16
        {
            .capacity = 16
            .buffer = cast([*] u8) &.padding[0]
            return
        }

        @assert(false)
    }

    mtd const asString()->string
    {
        return @mkstring(.buffer, .length)
    }

    mtd opPostCopy()
    {
        if .buffer do
            .buffer = cast([*] u8) &.padding[0]
    }

    mtd opDrop()
    {
        LastInlineBufferTextDropAddr = cast([*] void) &me
        if .buffer do
            @assert(.buffer == cast([*] u8) &.padding[0])
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
    entries:  [*] HashLikeEntry'(K, V)
    capacity: u64
}

impl HashLikeTable
{
    mtd add(key: K, value: V)
    {
        .entries[0].key = #nodrop key
        .entries[0].value = #nodrop value
        .entries[0].hash = 2
    }

    mtd free()
    {
        for i in .capacity where .entries[i].hash >= 1 do
            @drop(&.entries[i].value)
        @free(.entries)
        .entries = null
        .capacity = 0
    }
}

func makeInlineBufferText(value: string)->InlineBufferText
{
    var result: InlineBufferText
    result = value
    return result
}

#test
{
    var slot: CopySlot'SelfPointerValue
    var src: SelfPointerValue
    src.init(7)

    slot.assign(src)

    @assert(slot.value.first() == 7)
    @assert(slot.value.buffer == cast([*] u8) &slot.value.storage[0])
}

#test
{
    let entries = cast([*] CopySlot'SelfPointerValue) @alloc(#sizeof(CopySlot'SelfPointerValue))
    defer @free(entries)
    @memset(entries, 0, #sizeof(CopySlot'SelfPointerValue))

    var table: EntryArray'SelfPointerValue
    table.entries = entries

    var src: SelfPointerValue
    src.init(9)

    table.addAt(0, src)

    @assert(table.entries[0].value.first() == 9)
    @assert(table.entries[0].value.buffer == cast([*] u8) &table.entries[0].value.storage[0])
    @drop(&table.entries[0].value)
}

#test
{
    let entries = cast([*] CopySlot'InlineBufferText) @alloc(#sizeof(CopySlot'InlineBufferText))
    defer @free(entries)
    @memset(entries, 0, #sizeof(CopySlot'InlineBufferText))

    var table: EntryArray'InlineBufferText
    table.entries = entries

    table.addAt(0, makeInlineBufferText("swag"))

    @assert(table.entries[0].value.asString() == "swag")
    @assert(table.entries[0].value.buffer == cast([*] u8) &table.entries[0].value.padding[0])
    @drop(&table.entries[0].value)
}

#test
{
    let entries = cast([*] HashLikeEntry'(string, InlineBufferText)) @alloc(#sizeof(HashLikeEntry'(string, InlineBufferText)))
    @memset(entries, 0, #sizeof(HashLikeEntry'(string, InlineBufferText)))

    var table: HashLikeTable'(string, InlineBufferText)
    table.entries = entries
    table.capacity = 1

    table.add("alpha", makeInlineBufferText("one"))

    @assert(table.entries[0].hash == 2)
    @assert(table.entries[0].key == "alpha")
    @assert(table.entries[0].value.asString() == "one")
    @assert(table.entries[0].value.buffer == cast([*] u8) &table.entries[0].value.padding[0])
    table.free()
}

#test
{
    let entries = cast([*] HashLikeEntry'(string, InlineBufferText)) @alloc(#sizeof(HashLikeEntry'(string, InlineBufferText)))
    @memset(entries, 0, #sizeof(HashLikeEntry'(string, InlineBufferText)))

    var table: HashLikeTable'(string, InlineBufferText)
    table.entries = entries
    table.capacity = 1

    table.add("alpha", "one")
    let expectedDropAddr = cast([*] void) &table.entries[0].value

    @assert(table.entries[0].hash == 2)
    @assert(table.entries[0].key == "alpha")
    @assert(table.entries[0].value.asString() == "one")
    @assert(table.entries[0].value.buffer == cast([*] u8) &table.entries[0].value.padding[0])
    LastInlineBufferTextDropAddr = null
    table.free()
    @assert(LastInlineBufferTextDropAddr == expectedDropAddr)
}

#test
{
    let entries = cast([*] HashLikeEntry'(string, InlineBufferText)) @alloc(#sizeof(HashLikeEntry'(string, InlineBufferText)))
    @memset(entries, 0, #sizeof(HashLikeEntry'(string, InlineBufferText)))

    var table: HashLikeTable'(string, InlineBufferText)
    table.entries = entries
    table.capacity = 1

    var value: InlineBufferText = "one"
    table.add("alpha", value)

    @assert(table.entries[0].hash == 2)
    @assert(table.entries[0].key == "alpha")
    @assert(table.entries[0].value.asString() == "one")
    @assert(table.entries[0].value.buffer == cast([*] u8) &table.entries[0].value.padding[0])
    table.free()
}
