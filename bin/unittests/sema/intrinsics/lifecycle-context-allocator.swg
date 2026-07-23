#global private
using Swag

var DropCount: u32 = 0
var DropTrace: u64 = 0

func resetDropHooks()
{
    DropCount = 0
    DropTrace = 0
}

func helperFree(buffer: #null [*] void, size: u64, allocator: #null IAllocator = null)
{
    if !buffer do
        return

    var req: AllocatorRequest
    req.size    = size
    req.address = buffer

    let talloc = allocator orelse @getcontext().allocator
    talloc.free(&req)
}

func helperRealloc(buffer: #null [*] void, newSize: u64, oldSize: u64, allocator: #null IAllocator = null)->#null [*] void
{
    var req: AllocatorRequest
    req.address = buffer
    req.size    = newSize
    req.oldSize = oldSize

    let talloc = allocator orelse @getcontext().allocator
    talloc.realloc(&req)
    return req.address
}

func memoryLikeFree(buffer: #null [*] void, size: u64, allocator: #null IAllocator = null, hint: #null string = null, loc = #callerlocation)
{
    if !buffer do
        return

    var req: AllocatorRequest
    req.callerLoc = loc
    req.size      = size
    req.address   = buffer
    req.hint      = hint

    let talloc = allocator orelse @getcontext().allocator
    talloc.free(&req)
}

func memoryLikeRealloc(buffer: #null [*] void, newSize: u64, oldSize: u64, allocator: #null IAllocator = null, alignment: u16 = 0, hint: #null string = null, loc = #callerlocation)->#null [*] void
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.address   = buffer
    req.size      = newSize
    req.oldSize   = oldSize
    req.alignment = alignment

    let talloc = allocator orelse @getcontext().allocator
    talloc.realloc(&req)
    return req.address
}

func encodeByteTrace(buffer: #null [*] u8, count: u64)->u64
{
    var result: u64 = 0
    for i in count do
        result = result * 100 + cast(u64) buffer[i]
    return result * 100 + count
}

func encodeTrackedTrace(buffer: #null [*] DropTracked, count: u64)->u64
{
    var result: u64 = 0
    for i in count do
        result = result * 100 + cast(u64) buffer[i].value
    return result * 100 + count
}

struct ByteInitInfo
{
    firstTrace:  u64
    secondTrace: u64
    count:       u64
    capacity:    u64
}

struct DropRunInfo
{
    liveTrace: u64
    drops:     u32
    dropTrace: u64
    count:     u64
    capacity:  u64
}

struct DropTracked
{
    value: s32 = 9
}

impl DropTracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(u64) .value
    }
}

struct DirectByteBuffer
{
    allocator: #null IAllocator
    buffer:    #null [*] u8
    count:     u64
    capacity:  u64
}

impl DirectByteBuffer
{
    mtd opDrop() { .free() }

    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return
        if .allocator == null do
            .allocator = @getcontext().allocator

        var req: AllocatorRequest
        req.address = .buffer
        req.size    = newCapacity
        req.oldSize = .capacity
        .allocator.realloc(&req)
        .buffer   = cast(#null [*] u8) req.address
        .capacity = newCapacity
    }

    mtd resize(newCount: u64)
    {
        if newCount == .count do
            return
        if newCount > .count
        {
            .reserve(newCount)
            @init(.buffer + .count, newCount - .count)
        }
        else
        {
            @drop(.buffer + newCount, .count - newCount)
        }

        .count = newCount
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)

        var req: AllocatorRequest
        req.size    = .capacity
        req.address = .buffer
        .allocator.free(&req)
        .buffer           = null
        .count, .capacity = 0
    }
}

struct HelperByteBuffer
{
    allocator: #null IAllocator
    buffer:    #null [*] u8
    count:     u64
    capacity:  u64
}

impl HelperByteBuffer
{
    mtd opDrop() { .free() }

    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return
        if .allocator == null do
            .allocator = @getcontext().allocator

        .buffer   = cast(#null [*] u8) helperRealloc(.buffer, newCapacity, .capacity, .allocator)
        .capacity = newCapacity
    }

    mtd resize(newCount: u64)
    {
        if newCount == .count do
            return
        if newCount > .count
        {
            .reserve(newCount)
            @init(.buffer + .count, newCount - .count)
        }
        else
        {
            @drop(.buffer + newCount, .count - newCount)
        }

        .count = newCount
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)
        helperFree(.buffer, .capacity, .allocator)
        .buffer           = null
        .count, .capacity = 0
    }
}

struct MemoryTrackedBuffer
{
    allocator: #null IAllocator
    buffer:    #null [*] DropTracked
    count:     u64
    capacity:  u64
}

impl MemoryTrackedBuffer
{
    mtd opDrop() { .free() }

    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return
        if .allocator == null do
            .allocator = @getcontext().allocator

        .buffer   = cast(#null [*] DropTracked) memoryLikeRealloc(.buffer, newCapacity * #sizeof(DropTracked), .capacity * #sizeof(DropTracked), .allocator)
        .capacity = newCapacity
    }

    mtd resize(newCount: u64, seed: s32 = 9)
    {
        if newCount == .count do
            return
        if newCount > .count
        {
            .reserve(newCount)
            @init(.buffer + .count, newCount - .count)(seed)
        }
        else
        {
            @drop(.buffer + newCount, .count - newCount)
        }

        .count = newCount
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)
        memoryLikeFree(.buffer, .capacity * #sizeof(DropTracked), .allocator)
        .buffer           = null
        .count, .capacity = 0
    }
}

func directAllocatorRunInitInfo()->ByteInitInfo
{
    var values: DirectByteBuffer
    values.resize(4)
    let firstTrace = encodeByteTrace(values.buffer, values.count)

    values.buffer[0] = 3
    values.buffer[1] = 7
    values.resize(2)
    values.resize(5)
    let secondTrace = encodeByteTrace(values.buffer, values.count)

    let count = values.count
    let capacity = values.capacity
    values.free()
    return {firstTrace, secondTrace, count, capacity}
}

func helperAllocatorRunInitInfo()->ByteInitInfo
{
    var values: HelperByteBuffer
    values.resize(3)
    let firstTrace = encodeByteTrace(values.buffer, values.count)

    values.buffer[0] = 4
    values.buffer[2] = 9
    values.resize(1)
    values.resize(4)
    let secondTrace = encodeByteTrace(values.buffer, values.count)

    let count = values.count
    let capacity = values.capacity
    values.free()
    return {firstTrace, secondTrace, count, capacity}
}

func memoryAllocatorRunDropInfo()->DropRunInfo
{
    resetDropHooks()

    var values: MemoryTrackedBuffer
    values.resize(4, 9)
    for i in 4 do
        values.buffer[i].value = cast(s32) (i + 1)

    values.resize(2, 8)
    values.resize(5, 8)
    let liveTrace = encodeTrackedTrace(values.buffer, values.count)
    values.free()
    return {liveTrace, DropCount, DropTrace, values.count, values.capacity}
}

func semaTest001()
{
    const V = #run directAllocatorRunInitInfo()
    #assert(V.firstTrace == 4)
    #assert(V.secondTrace == 30_700_000_005)
    #assert(V.count == 5)
    #assert(V.capacity == 5)
}

func semaTest002()
{
    const V = #run helperAllocatorRunInitInfo()
    #assert(V.firstTrace == 3)
    #assert(V.secondTrace == 400000004)
    #assert(V.count == 4)
    #assert(V.capacity == 4)
}

func semaTest003()
{
    const V = #run memoryAllocatorRunDropInfo()
    #assert(V.liveTrace == 10208080805)
    #assert(V.drops == 7)
    #assert(V.dropTrace == 3040102080808)
    #assert(V.count == 0)
    #assert(V.capacity == 0)
}
