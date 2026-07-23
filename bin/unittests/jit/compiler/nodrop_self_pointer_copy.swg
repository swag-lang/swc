#global private

var LastInlineBufferTextDropAddr:       #null [*] void
var LastInlineBufferTextDropBuffer:     #null [*] u8
var ExpectedInlineBufferTextDropAddr:   #null [*] void
var ExpectedInlineBufferTextDropBuffer: #null [*] u8

struct SelfPointerValue
{
    storage: [8] u8
    buffer:  #null [*] u8
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
    entries: #null [*] CopySlot'T
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
    buffer:    #null [*] u8
    length:    u64
    capacity:  u64
    allocator: #null IAllocator
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
            .buffer   = cast([*] u8) &.padding[0]
            return
        }

        @assert(false)
    }

    mtd const asString()->string
    {
        return @mkstring(notnull .buffer, .length)
    }

    mtd opPostCopy()
    {
        if .buffer do
            .buffer = cast([*] u8) &.padding[0]
    }

    mtd opDrop()
    {
        let dropAddr = cast([*] void) &me
        LastInlineBufferTextDropAddr = dropAddr
        if ExpectedInlineBufferTextDropAddr
        {
            @assert(dropAddr == ExpectedInlineBufferTextDropAddr)
            LastInlineBufferTextDropBuffer = .buffer
            if ExpectedInlineBufferTextDropBuffer do
                @assert(.buffer == ExpectedInlineBufferTextDropBuffer)
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
    entries:  #null [*] HashLikeEntry'(K, V)
    capacity: u64
}

impl HashLikeTable
{
    mtd add(key: K, value: V)
    {
        .entries[0].key   = #nodrop key
        .entries[0].value = #nodrop value
        .entries[0].hash  = 2
    }

    mtd valueAddr(index: u64)->[*] void
    {
        return cast([*] void) &.entries[index].value
    }

    mtd free()
    {
        for i in .capacity where .entries[i].hash >= 1 do
            @drop(&.entries[i].value)
        @free(notnull .entries)
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
    @drop(ptr)
}

#test
{
    var slot: CopySlot'SelfPointerValue
    var src:  SelfPointerValue
    src.init(7)

    slot.assign(src)

    @assert(slot.value.first() == 7)
    @assert(slot.value.buffer == cast([*] u8) &slot.value.storage[0])
}

#test
{
    let entries = cast([*] CopySlot'SelfPointerValue) notnull @alloc(#sizeof(CopySlot'SelfPointerValue))
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
    let entries = cast([*] CopySlot'InlineBufferText) notnull @alloc(#sizeof(CopySlot'InlineBufferText))
    defer @free(entries)
    @memset(entries, 0, #sizeof(CopySlot'InlineBufferText))

    var table: EntryArray'InlineBufferText
    table.entries = entries

    table.addAt(0, makeInlineBufferText("swag"))

    @assert(table.entries[0].value.asString() == "swag")
    @assert(table.entries[0].value.buffer == cast([*] u8) &table.entries[0].value.padding[0])
    @drop(&table.entries[0].value)
}

#if true
{
    // Still broken: this warmup on `HashLikeTable'(string, InlineBufferText)` can corrupt the
    // later `HashLikeTable'(s32, InlineBufferText).free()` specialization in the same module.
    // Kept commented until that compiler bug is fixed.
    #test
    {
        let entries = cast([*] HashLikeEntry'(string, InlineBufferText)) notnull @alloc(#sizeof(HashLikeEntry'(string, InlineBufferText)))
        @memset(entries, 0, #sizeof(HashLikeEntry'(string, InlineBufferText)))

        var table: HashLikeTable'(string, InlineBufferText)
        table.entries  = entries
        table.capacity = 1

        table.add("alpha", makeInlineBufferText("one"))
        let expectedDropAddr = cast([*] void) &table.entries[0].value
        let expectedDropBuffer = cast([*] u8) &table.entries[0].value.padding[0]
        @assert(table.valueAddr(0) == expectedDropAddr)

        @assert(table.entries[0].hash == 2)
        @assert(table.entries[0].key == "alpha")
        @assert(table.entries[0].value.asString() == "one")
        @assert(table.entries[0].value.buffer == expectedDropBuffer)
        LastInlineBufferTextDropAddr   = null
        LastInlineBufferTextDropBuffer = null
        @free(entries)
    }

// A second variant was reduced away while isolating the order-dependent breakage above.
}

#test
{
    let entries = cast([*] HashLikeEntry'(s32, InlineBufferText)) notnull @alloc(#sizeof(HashLikeEntry'(s32, InlineBufferText)))
    @memset(entries, 0, #sizeof(HashLikeEntry'(s32, InlineBufferText)))

    var table: HashLikeTable'(s32, InlineBufferText)
    table.entries  = entries
    table.capacity = 1

    table.add(7, "one")
    let expectedDropAddr = table.valueAddr(0)
    let expectedDropBuffer = cast([*] u8) &table.entries[0].value.padding[0]
    LastInlineBufferTextDropAddr       = null
    LastInlineBufferTextDropBuffer     = null
    ExpectedInlineBufferTextDropAddr   = expectedDropAddr
    ExpectedInlineBufferTextDropBuffer = expectedDropBuffer
    table.free()
    @assert(LastInlineBufferTextDropAddr == expectedDropAddr)
    @assert(LastInlineBufferTextDropBuffer == expectedDropBuffer)
}

#if false
{
    #test
    {
        let entries = cast([*] HashLikeEntry'(s32, InlineBufferText)) notnull @alloc(#sizeof(HashLikeEntry'(s32, InlineBufferText)))
        @memset(entries, 0, #sizeof(HashLikeEntry'(s32, InlineBufferText)))

        var table: HashLikeTable'(s32, InlineBufferText)
        table.entries  = entries
        table.capacity = 1

        table.add(7, "one")
        let expectedDropAddr = cast([*] void) &table.entries[0].value
        let expectedDropBuffer = cast([*] u8) &table.entries[0].value.padding[0]

        LastInlineBufferTextDropAddr       = null
        LastInlineBufferTextDropBuffer     = null
        ExpectedInlineBufferTextDropAddr   = expectedDropAddr
        ExpectedInlineBufferTextDropBuffer = expectedDropBuffer
        table.freeViaPointer()
        @assert(LastInlineBufferTextDropAddr == expectedDropAddr)
        @assert(LastInlineBufferTextDropBuffer == expectedDropBuffer)
    }

    #test
    {
        let entries = cast([*] HashLikeEntry'(s32, InlineBufferText)) notnull @alloc(#sizeof(HashLikeEntry'(s32, InlineBufferText)))
        @memset(entries, 0, #sizeof(HashLikeEntry'(s32, InlineBufferText)))

        var table: HashLikeTable'(s32, InlineBufferText)
        table.entries  = entries
        table.capacity = 1

        table.add(7, "one")
        let expectedDropAddr = cast([*] void) &table.entries[0].value
        let expectedDropBuffer = cast([*] u8) &table.entries[0].value.padding[0]

        LastInlineBufferTextDropAddr       = null
        LastInlineBufferTextDropBuffer     = null
        ExpectedInlineBufferTextDropAddr   = expectedDropAddr
        ExpectedInlineBufferTextDropBuffer = expectedDropBuffer
        table.freeViaHelper()
        @assert(LastInlineBufferTextDropAddr == expectedDropAddr)
        @assert(LastInlineBufferTextDropBuffer == expectedDropBuffer)
    }
}

#if true
{
    // Still order-dependent in the full JIT suite: passes when isolated, but a larger compiler module
    // can make this `string` specialization compare against the wrong drop slot.
    #test
    {
        let entries = cast([*] HashLikeEntry'(string, InlineBufferText)) notnull @alloc(#sizeof(HashLikeEntry'(string, InlineBufferText)))
        @memset(entries, 0, #sizeof(HashLikeEntry'(string, InlineBufferText)))

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
        @assert(LastInlineBufferTextDropAddr == ExpectedInlineBufferTextDropAddr)
        @assert(LastInlineBufferTextDropBuffer == expectedDropBuffer)
    }
}

#if false
{
    #test
    {
        var value: InlineBufferText = "one"
        SWAG_HAS_UNUSED = value
    }
}
