#global private
using Swag

var DropCount: u32 = 0
var DropTrace: u64 = 0

func resetDropHooks()
{
    DropCount = 0
    DropTrace = 0
}

func helperFree(buffer: [*] void?, size: u64, allocator: IAllocator? = null)
{
    if !buffer do
        return

    var req: AllocatorRequest
    req.size    = size
    req.address = buffer

    let talloc = (allocator orelse Swag.getContext().allocator)!
    talloc.free(&req)
}

func helperRealloc(buffer: [*] void?, newSize: u64, oldSize: u64, allocator: IAllocator? = null)->[*] void?
{
    var req: AllocatorRequest
    req.address = buffer
    req.size    = newSize
    req.oldSize = oldSize

    let talloc = (allocator orelse Swag.getContext().allocator)!
    talloc.realloc(&req)
    return req.address
}

func memoryLikeFree(buffer: [*] void?, size: u64, allocator: IAllocator? = null, hint: string? = null, loc = #callerlocation)
{
    if !buffer do
        return

    var req: AllocatorRequest
    req.callerLoc = loc
    req.size      = size
    req.address   = buffer
    req.hint      = hint

    let talloc = (allocator orelse Swag.getContext().allocator)!
    talloc.free(&req)
}

func memoryLikeRealloc(buffer: [*] void?, newSize: u64, oldSize: u64, allocator: IAllocator? = null, alignment: u16 = 0, hint: string? = null, loc = #callerlocation)->[*] void?
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.address   = buffer
    req.size      = newSize
    req.oldSize   = oldSize
    req.alignment = alignment

    let talloc = (allocator orelse Swag.getContext().allocator)!
    talloc.realloc(&req)
    return req.address
}

func encodeByteTrace(buffer: [*] u8?, count: u64)->u64
{
    var result: u64 = 0
    if buffer != null
    {
        for i in count do
            result = result * 100 + cast(u64) buffer[i]
    }
    return result * 100 + count
}

func encodeTrackedTrace(buffer: [*] DropTracked?, count: u64)->u64
{
    var result: u64 = 0
    if buffer != null
    {
        for i in count do
            result = result * 100 + cast(u64) buffer[i].value
    }
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
    allocator: IAllocator?
    buffer:    [*] u8?
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
            .allocator = Swag.getContext().allocator

        var req: AllocatorRequest
        req.address = .buffer
        req.size    = newCapacity
        req.oldSize = .capacity
        let talloc = .allocator!
        talloc.realloc(&req)
        .buffer   = cast([*] u8?) req.address
        .capacity = newCapacity
    }

    mtd resize(newCount: u64)
    {
        if newCount == .count do
            return
        if newCount > .count
        {
            .reserve(newCount)
            Swag.init(.buffer + .count, newCount - .count)
        }
        else
        {
            Swag.drop(.buffer + newCount, .count - newCount)
        }

        .count = newCount
    }

    mtd free()
    {
        if !.buffer do
            return

        Swag.drop(.buffer, .count)

        var req: AllocatorRequest
        req.size    = .capacity
        req.address = .buffer
        let talloc = .allocator!
        talloc.free(&req)
        .buffer           = null
        .count, .capacity = 0
    }
}

struct HelperByteBuffer
{
    allocator: IAllocator?
    buffer:    [*] u8?
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
            .allocator = Swag.getContext().allocator

        .buffer   = cast([*] u8?) helperRealloc(.buffer, newCapacity, .capacity, .allocator)
        .capacity = newCapacity
    }

    mtd resize(newCount: u64)
    {
        if newCount == .count do
            return
        if newCount > .count
        {
            .reserve(newCount)
            Swag.init(.buffer + .count, newCount - .count)
        }
        else
        {
            Swag.drop(.buffer + newCount, .count - newCount)
        }

        .count = newCount
    }

    mtd free()
    {
        if !.buffer do
            return

        Swag.drop(.buffer, .count)
        helperFree(.buffer, .capacity, .allocator)
        .buffer           = null
        .count, .capacity = 0
    }
}

struct MemoryTrackedBuffer
{
    allocator: IAllocator?
    buffer:    [*] DropTracked?
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
            .allocator = Swag.getContext().allocator

        .buffer   = cast([*] DropTracked?) memoryLikeRealloc(.buffer, newCapacity * #sizeof(DropTracked), .capacity * #sizeof(DropTracked), .allocator)
        .capacity = newCapacity
    }

    mtd resize(newCount: u64, seed: s32 = 9)
    {
        if newCount == .count do
            return
        if newCount > .count
        {
            .reserve(newCount)
            Swag.init(.buffer + .count, newCount - .count)(seed)
        }
        else
        {
            Swag.drop(.buffer + newCount, .count - newCount)
        }

        .count = newCount
    }

    mtd free()
    {
        if !.buffer do
            return

        Swag.drop(.buffer, .count)
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

    let buf = values.buffer!
    buf[0] = 3
    buf[1] = 7
    values.resize(2)
    values.resize(5)
    let secondTrace = encodeByteTrace(values.buffer, values.count)

    let count    = values.count
    let capacity = values.capacity
    values.free()
    return {firstTrace, secondTrace, count, capacity}
}

func helperAllocatorRunInitInfo()->ByteInitInfo
{
    var values: HelperByteBuffer
    values.resize(3)
    let firstTrace = encodeByteTrace(values.buffer, values.count)

    let buf = values.buffer!
    buf[0] = 4
    buf[2] = 9
    values.resize(1)
    values.resize(4)
    let secondTrace = encodeByteTrace(values.buffer, values.count)

    let count    = values.count
    let capacity = values.capacity
    values.free()
    return {firstTrace, secondTrace, count, capacity}
}

func memoryAllocatorRunDropInfo()->DropRunInfo
{
    resetDropHooks()

    var values: MemoryTrackedBuffer
    values.resize(4, 9)
    let buf = values.buffer!
    for i in 4 do
        buf[i].value = cast(s32) (i + 1)

    values.resize(2, 8)
    values.resize(5, 8)
    let liveTrace = encodeTrackedTrace(values.buffer, values.count)
    values.free()
    return {liveTrace, DropCount, DropTrace, values.count, values.capacity}
}

const DirectRunInfo = #run directAllocatorRunInitInfo()
const HelperRunInfo = #run helperAllocatorRunInitInfo()
const MemoryRunInfo = #run memoryAllocatorRunDropInfo()

#test
{
    Swag.assert(DirectRunInfo.firstTrace == 4)
    Swag.assert(DirectRunInfo.secondTrace == 30_700_000_005)
    Swag.assert(DirectRunInfo.count == 5)
    Swag.assert(DirectRunInfo.capacity == 5)

    let v = directAllocatorRunInitInfo()
    Swag.assert(v.firstTrace == DirectRunInfo.firstTrace)
    Swag.assert(v.secondTrace == DirectRunInfo.secondTrace)
    Swag.assert(v.count == DirectRunInfo.count)
    Swag.assert(v.capacity == DirectRunInfo.capacity)
}

#test
{
    Swag.assert(HelperRunInfo.firstTrace == 3)
    Swag.assert(HelperRunInfo.secondTrace == 400000004)
    Swag.assert(HelperRunInfo.count == 4)
    Swag.assert(HelperRunInfo.capacity == 4)

    let v = helperAllocatorRunInitInfo()
    Swag.assert(v.firstTrace == HelperRunInfo.firstTrace)
    Swag.assert(v.secondTrace == HelperRunInfo.secondTrace)
    Swag.assert(v.count == HelperRunInfo.count)
    Swag.assert(v.capacity == HelperRunInfo.capacity)
}

#test
{
    Swag.assert(MemoryRunInfo.liveTrace == 10208080805)
    Swag.assert(MemoryRunInfo.drops == 7)
    Swag.assert(MemoryRunInfo.dropTrace == 3040102080808)
    Swag.assert(MemoryRunInfo.count == 0)
    Swag.assert(MemoryRunInfo.capacity == 0)

    let v = memoryAllocatorRunDropInfo()
    Swag.assert(v.liveTrace == MemoryRunInfo.liveTrace)
    Swag.assert(v.drops == MemoryRunInfo.drops)
    Swag.assert(v.dropTrace == MemoryRunInfo.dropTrace)
    Swag.assert(v.count == MemoryRunInfo.count)
    Swag.assert(v.capacity == MemoryRunInfo.capacity)
}
