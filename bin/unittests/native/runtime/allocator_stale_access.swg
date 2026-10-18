#global if #hastag("Swag.AllocatorDiagnostics")
#global private

using Swag

// Electric mode and the diagnostic quarantine must report an access to memory the program no
// longer owns: a freed electric payload at the access itself, a write into an electric block's
// slack or into a quarantined payload when the allocator next looks at the block.

func electricAllocator(allocator: *Allocator)->IAllocator
{
    allocator.setup()
    allocator.configure(true, false, false, false, false)
    return Swag.makeInterface(allocator, #typeof(allocator[]), IAllocator)
}

func quarantineAllocator(allocator: *Allocator)->IAllocator
{
    allocator.setup()
    allocator.configure(false, false, false, true, true)
    return Swag.makeInterface(allocator, #typeof(allocator[]), IAllocator)
}

func allocOne(itf: IAllocator, size: u64, alignment: u32 = 0)->u64
{
    var request: AllocatorRequest
    request.size      = size
    request.alignment = alignment
    itf.alloc(&request)
    Swag.assert(request.address != null)
    return cast(u64, request.address)
}

// Accesses through an integer address, which the static analysis does not follow: the stale and
// out-of-bounds accesses below are the point of these tests.
func readAt(address: u64)->u8 => cast(const *u8, address)[]

func writeAt(address: u64, value: u8)
{
    cast(*u8, address)[] = value
}

func freeAt(itf: IAllocator, address: u64)
{
    var request: AllocatorRequest
    request.address = cast(*void, address)
    itf.free(&request)
}

// A panic caught inside an allocator operation abandons the frame holding the diagnostic lock.
func recoverLock(allocator: *Allocator)
{
    allocator.mutex.unlock()
}

// A freed electric payload is inaccessible: a read or a write through a pointer kept past the
// free faults at the access, whatever the size of the block and the offset into it. The payload
// pages go back to the system; the header page and the reservation remain.
#test
{
    if Swag.jit() do
        return

    var allocator: Allocator
    let itf = electricAllocator(&allocator)
    defer allocator.releaseAll()

    for size in [1'u64, 64, 129, 4096, 5000, 100_000]
    {
        let address = allocOne(itf, size)
        writeAt(address, 7)
        writeAt(address + size - 1, 9)
        freeAt(itf, address)
        Swag.assert(allocator.headerOf(address).commitSize == AllocatorCommitGranularity)

        // The read lands in a captured byte so that optimized code cannot drop it.
        var seen: u8
        for offset in [0'u64, size / 2, size - 1]
        {
            let read  = Swag.catchPanic(func|address, offset, &seen|() { seen = readAt(address + offset) })
            let write = Swag.catchPanic(func|address, offset|() { writeAt(address + offset, 1) })
            Swag.assert(read.raised and read.message() == "memory access violation")
            Swag.assert(write.raised and write.message() == "memory access violation")
        }
    }

    Swag.assert(allocator.stats().countFree == 6)
}

// An electric block freed twice is reported through its header, which stays readable while the
// payload does not.
#test
{
    var allocator: Allocator
    let itf = electricAllocator(&allocator)
    defer allocator.releaseAll()

    let address = allocOne(itf, 48)
    freeAt(itf, address)
    let caught = Swag.catchPanic(func|itf, address|() { freeAt(itf, address) })
    Swag.assert(caught.raised and caught.message() == "memory block is freed twice")
    recoverLock(&allocator)
}

// A write past the end of an electric block lands in the alignment slack before the guard page and
// is reported when the block is freed, whatever the alignment; a write past the slack faults at once.
#test
{
    var allocator: Allocator
    let itf = electricAllocator(&allocator)
    defer allocator.releaseAll()

    for alignment in [16'u32, 64, 4096]
    {
        let address = allocOne(itf, 129, alignment)
        Swag.assert((address & (alignment - 1)) == 0)
        let header = allocator.headerOf(address)
        Swag.assert(header.isElectric and header.userAddr == address)
        let slack = cast(u64, header.allocAddr) + header.allocSize - address - 129
        Swag.assert(slack > 0 and slack < alignment)

        writeAt(address + 129, 1)
        let caught = Swag.catchPanic(func|itf, address|() { freeAt(itf, address) })
        Swag.assert(caught.raised and caught.message() == "memory block was written past its end")
        recoverLock(&allocator)
    }

    if Swag.jit() do
        return

    let address = allocOne(itf, 129, 16)
    let header  = allocator.headerOf(address)
    let guard   = cast(u64, header.allocAddr) + header.allocSize
    let caught  = Swag.catchPanic(func|guard|() { writeAt(guard, 1) })
    Swag.assert(caught.raised and caught.message() == "memory access violation")
    freeAt(itf, address)
}

// A stale pointer kept across the reallocation of an electric block cannot reach the old payload.
#test
{
    if Swag.jit() do
        return

    var allocator: Allocator
    let itf = electricAllocator(&allocator)
    defer allocator.releaseAll()

    var request: AllocatorRequest
    request.size = 100
    itf.alloc(&request)
    let old = cast(u64, request.address)
    for i in 100 do
        writeAt(old + i, cast #wrap (u8, i))

    request.oldSize = 100
    request.size    = 3000
    itf.realloc(&request)
    let moved = cast(u64, request.address)
    Swag.assert(moved != 0 and moved != old)
    for i in 100 do
        Swag.assert(readAt(moved + i) == cast #wrap (u8, i))

    var seen: u8
    let caught = Swag.catchPanic(func|old, &seen|() { seen = readAt(old) })
    Swag.assert(caught.raised and caught.message() == "memory access violation")
    itf.free(&request)
}

// With memory filling on, a write into a quarantined payload is reported when the allocator next
// checks the block: in 'checkAllMemory', and when the block leaves the quarantine.
#test
{
    var allocator: Allocator
    let itf = quarantineAllocator(&allocator)
    defer allocator.releaseAll()

    let address = allocOne(itf, 200)
    freeAt(itf, address)
    Swag.assert(readAt(address + 100) == Allocator.FreeByte)
    allocator.checkAllMemory()

    writeAt(address + 100, 0x11)
    let checked = Swag.catchPanic(func|&allocator|() { allocator.checkAllMemory() })
    Swag.assert(checked.raised and checked.message() == "memory block was written after being freed")

    allocator.maxQuarantineBytes = 1
    let evicted = Swag.catchPanic(func|itf|() { freeAt(itf, allocOne(itf, 200)) })
    Swag.assert(evicted.raised and evicted.message() == "memory block was written after being freed")
    recoverLock(&allocator)
}
