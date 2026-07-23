#global private

using Swag

const AllocatorScratchBufSize = 4096'u64

func makeAllocator(alloc: *Allocator, electricMode: bool = false, detectLeaks: bool = false, captureStack: bool = false, trackAllocations: bool = false, fillMemory: bool = true)->IAllocator
{
    alloc.setup()
    alloc.configure(electricMode, detectLeaks, captureStack, trackAllocations, fillMemory)
    return @mkinterface(alloc, #typeof(dref alloc), IAllocator)
}

func makeAllocatorScratch(scratch: *ScratchAllocator, alloc: *Allocator)->IAllocator
{
    let itf = makeAllocator(alloc, fillMemory: false)
    scratch.setCapacity(AllocatorScratchBufSize, itf)
    return @mkinterface(scratch, #typeof(dref scratch), IAllocator)
}

#if #os == Swag.TargetOs.Windows
{
    namespace AllocatorThreadTest
    {
        alias HANDLE = *void
        alias DWORD  = u32
        alias SIZE_T = u64
        alias LPTHREAD_START_ROUTINE = func(*void)->DWORD

        const INFINITE = 0xFFFF_FFFF'u32

        #[Swag.Foreign("kernel32")]
        {
            func CreateThread(lpThreadAttributes: #null *void, dwStackSize: SIZE_T, lpStartAddress: LPTHREAD_START_ROUTINE, lpParameter: *void, dwCreationFlags: DWORD, lpThreadId: *DWORD)->HANDLE;
            func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD;
            func CloseHandle(handle: HANDLE);
        }
    }

    struct AllocatorRemoteFreePayload
    {
        allocator: IAllocator
        address:   *void
        done:      *s32
    }

    func allocatorRemoteFreeThread(param: *void)->AllocatorThreadTest.DWORD
    {
        let payload = cast(*AllocatorRemoteFreePayload) param

        var req: AllocatorRequest
        req.address = payload.address
        req.size = 64
        payload.allocator.free(&req)

        @atomadd(payload.done, 1)
        return 0
    }
}

#test
{
    @assert(defaultAllocator().installed())

    if @jit() do
        return

    let allocator = @getcontext().allocator
    let runtimeItf = cast(const *Swag.Interface) &allocator
    @assert(runtimeItf.obj == defaultAllocator())
}

#test
{
    if @jit() do
        return

    let alloc = defaultAllocator()
    let beforeCount = alloc.countAlloc
    let beforeSize = alloc.sizeAlloc

    var req: AllocatorRequest
    req.size = 80
    @getcontext().allocator.alloc(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == beforeCount + 1)
    @assert(alloc.sizeAlloc == beforeSize + 80)

    let ptr = cast([*] u8) notnull req.address
    for i in 80 do
        ptr[i] = cast(u8) (i + 3)

    req.oldSize = 80
    req.size = 4096
    @getcontext().allocator.realloc(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == beforeCount + 1)
    @assert(alloc.sizeAlloc == beforeSize + 4096)

    let grown = cast([*] u8) notnull req.address
    for i in 80 do
        @assert(grown[i] == cast(u8) (i + 3))

    req.size = 4096
    @getcontext().allocator.free(&req)
    @assert(req.address == null)
    @assert(alloc.countAlloc == beforeCount)
    @assert(alloc.sizeAlloc == beforeSize)
}

#test
{
    if @jit() do
        return

    let alloc = defaultAllocator()
    let beforeCount = alloc.countAlloc
    let beforeSize = alloc.sizeAlloc

    var reqs: [12] AllocatorRequest
    for i in 12
    {
        reqs[i].size = 31 + cast(u64) i * 37
        if i % 3 == 0 do
            reqs[i].alignment = 64
        @getcontext().allocator.alloc(&reqs[i])
        @assert(reqs[i].address != null)

        let ptr = cast([*] u8) notnull reqs[i].address
        for j in reqs[i].size do
            ptr[j] = cast(u8) ((i + j) & 0xFF)
    }

    @assert(alloc.countAlloc == beforeCount + 12)

    var assertReq: AllocatorRequest
    assertReq.address = reqs[5].address
    @getcontext().allocator.assertAllocated(&assertReq)

    for i in 6
    {
        @getcontext().allocator.free(&reqs[i])
        @assert(reqs[i].address == null)
    }

    for i in 6 until 12
    {
        reqs[i].oldSize = reqs[i].size
        reqs[i].size += 1024
        @getcontext().allocator.realloc(&reqs[i])
        @assert(reqs[i].address != null)

        let ptr = cast([*] u8) notnull reqs[i].address
        for j in reqs[i].oldSize do
            @assert(ptr[j] == cast(u8) ((i + j) & 0xFF))
    }

    for i in 6 until 12
    {
        @getcontext().allocator.free(&reqs[i])
        @assert(reqs[i].address == null)
    }

    @assert(alloc.countAlloc == beforeCount)
    @assert(alloc.sizeAlloc == beforeSize)
}

#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeAllocatorScratch(&scratch, &alloc)

    let backing = cast(const *Swag.Interface) &scratch.allocator
    @assert(backing.obj == &alloc)
    @assert(alloc.countAlloc == 1)

    var req: AllocatorRequest
    req.size = 64
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)

    scratch.release()
    @assert(scratch.block == null)
    @assert(alloc.countAlloc == 0)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let backing = makeAllocator(&alloc, detectLeaks: true, captureStack: true, trackAllocations: true, fillMemory: true)
    scratch.setCapacity(AllocatorScratchBufSize, backing)
    let itf = @mkinterface(&scratch, #typeof(scratch), IAllocator)

    @assert(alloc.countAlloc == 1)

    var inBuffer: AllocatorRequest
    inBuffer.size = AllocatorScratchBufSize - 64
    itf.alloc(&inBuffer)
    @assert(inBuffer.address != null)
    @assert(alloc.countAlloc == 1)

    var leaked: AllocatorRequest
    leaked.size = 256
    itf.alloc(&leaked)
    @assert(leaked.address != null)
    @assert(scratch.totalLeak >= 256)
    @assert(alloc.countAlloc == 2)

    itf.free(&leaked)
    @assert(leaked.address == null)
    @assert(scratch.totalLeak == 0)
    @assert(alloc.countAlloc == 1)

    scratch.release()
    @assert(alloc.countAlloc == 0)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 64
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)
    @assert(alloc.sizeAlloc == 64)

    let ptr = cast([*] u8) notnull req.address
    for i in 64 do
        @assert(ptr[i] == Allocator.AllocByte)

    req.size = 64
    itf.free(&req)
    @assert(req.address == null)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 1)
    @assert(alloc.sizeCached >= 64)

    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 0
    itf.alloc(&req)
    @assert(req.address == null)

    req.address = null
    itf.free(&req)
    @assert(req.address == null)

    req.address = null
    req.size = 0
    itf.realloc(&req)
    @assert(req.address == null)

    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req1: AllocatorRequest
    req1.size = 48
    itf.alloc(&req1)
    let first = req1.address

    req1.size = 48
    itf.free(&req1)

    var req2: AllocatorRequest
    req2.size = 48
    itf.alloc(&req2)
    @assert(req2.address == first)

    req2.size = 48
    itf.free(&req2)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, electricMode: true)

    var req1: AllocatorRequest
    req1.size = 48
    itf.alloc(&req1)
    let first = req1.address

    req1.size = 48
    itf.free(&req1)

    var req2: AllocatorRequest
    req2.size = 48
    itf.alloc(&req2)
    @assert(req2.address != first)

    req2.size = 48
    itf.free(&req2)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 33
    itf.alloc(&req)
    let original = req.address

    let ptr = cast([*] u8) notnull req.address
    for i in 33 do
        ptr[i] = cast(u8) (i + 1)

    req.oldSize = 33
    req.size = 48
    itf.realloc(&req)
    @assert(req.address == original)

    let samePtr = cast([*] u8) notnull req.address
    for i in 33 do
        @assert(samePtr[i] == cast(u8) (i + 1))
    for i in 33 until 48 do
        @assert(samePtr[i] == Allocator.AllocByte)

    req.size = 48
    itf.free(&req)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 96
    itf.alloc(&req)
    let original = req.address
    @assert(original != null)

    let ptr = cast([*] u8) notnull original
    for i in 96 do
        ptr[i] = cast(u8) (255 - i)

    req.oldSize = 96
    req.size = 24
    itf.realloc(&req)
    @assert(req.address == original)

    let shrunk = cast([*] u8) notnull req.address
    for i in 24 do
        @assert(shrunk[i] == cast(u8) (255 - i))

    req.oldSize = 24
    req.size = 0
    itf.realloc(&req)
    @assert(req.address == null)

    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 24
    itf.alloc(&req)

    let ptr = cast([*] u8) notnull req.address
    for i in 24 do
        ptr[i] = cast(u8) (i * 3 + 7)

    req.oldSize = 24
    req.size = 2048
    itf.realloc(&req)
    @assert(req.address != null)

    let grown = cast([*] u8) notnull req.address
    for i in 24 do
        @assert(grown[i] == cast(u8) (i * 3 + 7))

    req.size = 2048
    itf.free(&req)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, fillMemory: false)

    var req: AllocatorRequest
    req.size = alloc.maxCachedSize + 1024
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)

    itf.free(&req)
    @assert(req.address == null)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeCached == 0)

    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 257
    req.alignment = 128
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 128 == 0)

    req.size = 257
    itf.free(&req)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true)
    @assert(alloc.captureAllocStack)

    var req: AllocatorRequest
    itf.freeAll(&req)
    @assert(req.address == null)

    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true)

    var req: AllocatorRequest
    req.size = 0
    itf.alloc(&req)
    @assert(req.address == null)

    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true)

    var req: AllocatorRequest
    req.size = 1
    itf.alloc(&req)
    @assert(req.address != null)

    itf.free(&req)
    @assert(req.address == null)

    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true)

    var req: AllocatorRequest
    req.size = 112
    itf.alloc(&req)
    @assert(req.address != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) (notnull req.address) - #sizeof(AllocatorHeader))
    @assert(header.magic == Allocator.MagicAlloc)
    @assert(header.stackCount <= @countof(header.stack))
    #if #os == Swag.TargetOs.Windows do
        if !@jit() do
            @assert(header.stackCount > 0)

    itf.free(&req)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, trackAllocations: true, fillMemory: true)

    var req: AllocatorRequest
    req.size = 128
    itf.alloc(&req)
    @assert(req.address != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) (notnull req.address) - #sizeof(AllocatorHeader))
    @assert(header.stackCount == 0)
    @assert(alloc.firstAlloc == header)

    var assertReq: AllocatorRequest
    assertReq.address = req.address
    itf.assertAllocated(&assertReq)

    itf.free(&req)
    @assert(req.address == null)
    @assert(alloc.firstFree == header)

    let freed = alloc.userAddress(header)
    for i in 128 do
        @assert(freed[i] == Allocator.FreeByte)

    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true, trackAllocations: true)

    var req: AllocatorRequest
    req.size = 128
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(alloc.firstAlloc != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) (notnull req.address) - #sizeof(AllocatorHeader))
    @assert(header == alloc.firstAlloc)
    @assert(header.stackCount <= @countof(header.stack))

    itf.free(&req)
    @assert(req.address == null)
    @assert(alloc.firstFree == header)

    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true, fillMemory: true)

    var req: AllocatorRequest
    req.size = 128
    itf.alloc(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) notnull req.address
    for i in 128 do
        @assert(ptr[i] == Allocator.AllocByte)

    let header = cast(*AllocatorHeader) (cast([*] u8) (notnull req.address) - #sizeof(AllocatorHeader))
    @assert(header.stackCount <= @countof(header.stack))

    itf.free(&req)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, detectLeaks: true, captureStack: true, trackAllocations: true)

    var req: AllocatorRequest
    req.size = 128
    req.hint = "debug-track-stack-no-fill"
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(alloc.firstAlloc != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) (notnull req.address) - #sizeof(AllocatorHeader))
    @assert(header == alloc.firstAlloc)
    @assert(header.stackCount <= @countof(header.stack))

    var assertReq: AllocatorRequest
    assertReq.address = req.address
    itf.assertAllocated(&assertReq)

    itf.free(&req)
    @assert(req.address == null)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, detectLeaks: true, captureStack: true, trackAllocations: true, fillMemory: true)

    var req: AllocatorRequest
    req.size = 128
    req.hint = "tracked-fill-regression"
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)
    @assert(alloc.firstAlloc != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) (notnull req.address) - #sizeof(AllocatorHeader))
    @assert(header == alloc.firstAlloc)
    @assert(header.magic == Allocator.MagicAlloc)
    @assert(alloc.footer(header).magic == Allocator.MagicAlloc)
    @assert(header.stackCount <= @countof(header.stack))
    #if #os == Swag.TargetOs.Windows do
        if !@jit() do
            @assert(header.stackCount > 0)

    var assertReq: AllocatorRequest
    assertReq.address = req.address
    itf.assertAllocated(&assertReq)

    itf.free(&req)
    @assert(req.address == null)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.firstAlloc == null)
    @assert(alloc.firstFree == header)
    @assert(header.magic == Allocator.MagicFree)
    @assert(alloc.footer(header).magic == Allocator.MagicFree)

    let freed = alloc.userAddress(header)
    for i in 128 do
        @assert(freed[i] == Allocator.FreeByte)

    alloc.checkAllMemory()
    alloc.releaseAll()
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeCached == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, detectLeaks: true, captureStack: true, trackAllocations: true, fillMemory: true)

    var reqs: [10] AllocatorRequest
    for i in 10
    {
        reqs[i].size = 64 + cast(u64) i * 17
        reqs[i].hint = "debug-mixed-regression"
        if i % 2 == 0 do
            reqs[i].alignment = 32
        itf.alloc(&reqs[i])
        @assert(reqs[i].address != null)
    }

    @assert(alloc.countAlloc == 10)
    alloc.checkAllMemory()

    for i in 5
    {
        itf.free(&reqs[i])
        @assert(reqs[i].address == null)
    }

    @assert(alloc.countAlloc == 5)
    @assert(alloc.countFree == 5)
    alloc.checkAllMemory()

    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeAlloc == 0)
    @assert(alloc.sizeFree == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, trackAllocations: true)

    var reqs: [4] AllocatorRequest
    for i in 4
    {
        reqs[i].size = (i + 1) * 96
        itf.alloc(&reqs[i])
        @assert(reqs[i].address != null)
    }

    @assert(alloc.countAlloc == 4)

    var req: AllocatorRequest
    itf.freeAll(&req)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeAlloc == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var reqs: [32] AllocatorRequest
    for i in 32
    {
        reqs[i].size = 32 + cast(u64) (i % 8) * 16
        itf.alloc(&reqs[i])
        @assert(reqs[i].address != null)

        itf.free(&reqs[i])
        @assert(reqs[i].address == null)
    }

    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree > 0)
    @assert(alloc.sizeCached > 0)

    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeCached == 0)

    var req: AllocatorRequest
    req.size = 64
    itf.alloc(&req)
    @assert(req.address != null)
    itf.free(&req)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 64
    itf.alloc(&req)
    @assert(req.address != null)

    itf.free(&req)
    @assert(alloc.countFree == 1)

    releaseAllocatorThreadCache()
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeCached == 0)
    alloc.releaseRetiredHeaps()
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    // Note: leak detection is intentionally left off here. This case verifies that
    // 'release()' frees an allocation that is still outstanding; enabling detectLeaks
    // would make release() dump a leak report to the test log for no added coverage.
    let itf = makeAllocator(&alloc, trackAllocations: true, fillMemory: true)

    var req: AllocatorRequest
    req.size = 77
    itf.alloc(&req)
    @assert(req.address != null)

    alloc.release()
    @assert(!alloc.installed())

    let itf2 = makeAllocator(&alloc, fillMemory: true)
    req.size = 33
    itf2.alloc(&req)
    @assert(req.address != null)

    itf2.free(&req)
    alloc.releaseAll()
}

#if #os == Swag.TargetOs.Windows
{
    #test
    {
        var alloc: Allocator
        let itf = makeAllocator(&alloc)

        var req: AllocatorRequest
        req.size = 64
        itf.alloc(&req)
        let first = req.address
        @assert(first != null)

        var done: s32 = 0
        var payload: AllocatorRemoteFreePayload = undefined
        payload.allocator = itf
        payload.address = notnull first
        payload.done = &done

        var threadId: AllocatorThreadTest.DWORD
        let handle = AllocatorThreadTest.CreateThread(null, 0, &allocatorRemoteFreeThread, &payload, 0, &threadId)
        @assert(handle != null)
        discard AllocatorThreadTest.WaitForSingleObject(handle, AllocatorThreadTest.INFINITE)
        AllocatorThreadTest.CloseHandle(handle)
        @assert(@atomcmpxchg(&done, 0, 0) == 1)

        var req2: AllocatorRequest
        req2.size = 64
        itf.alloc(&req2)
        @assert(req2.address == first)

        req2.size = 64
        itf.free(&req2)
        alloc.releaseAll()
    }

    #test
    {
        var alloc: Allocator
        let itf = makeAllocator(&alloc, detectLeaks: true, captureStack: true, trackAllocations: true, fillMemory: true)

        var req: AllocatorRequest
        req.size = 72
        itf.alloc(&req)
        let first = req.address
        @assert(first != null)

        var done: s32 = 0
        var payload: AllocatorRemoteFreePayload = undefined
        payload.allocator = itf
        payload.address = notnull first
        payload.done = &done

        var threadId: AllocatorThreadTest.DWORD
        let handle = AllocatorThreadTest.CreateThread(null, 0, &allocatorRemoteFreeThread, &payload, 0, &threadId)
        @assert(handle != null)
        discard AllocatorThreadTest.WaitForSingleObject(handle, AllocatorThreadTest.INFINITE)
        AllocatorThreadTest.CloseHandle(handle)
        @assert(@atomcmpxchg(&done, 0, 0) == 1)
        @assert(alloc.countAlloc == 0)
        @assert(alloc.countFree == 1)

        var freeAll: AllocatorRequest
        itf.freeAll(&freeAll)
        @assert(alloc.countFree == 0)
    }
}
