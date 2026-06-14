#global fileprivate

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
        req.mode = .Free
        req.address = payload.address
        req.size = 64
        payload.allocator.req(&req)

        @atomadd(payload.done, 1)
        return 0
    }
}

#test
{
    @assert(defaultAllocator().installed())

    let allocator = @getcontext().allocator
    let runtimeItf = cast(const *Swag.Interface) &allocator
    @assert(runtimeItf.obj == defaultAllocator())
}

#test
{
    let alloc = defaultAllocator()
    let beforeCount = alloc.countAlloc
    let beforeSize = alloc.sizeAlloc

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 80
    @getcontext().allocator.req(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == beforeCount + 1)
    @assert(alloc.sizeAlloc == beforeSize + 80)

    let ptr = cast([*] u8) req.address
    for i in 80 do
        ptr[i] = cast(u8) (i + 3)

    req.mode = .Realloc
    req.oldSize = 80
    req.size = 4096
    @getcontext().allocator.req(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == beforeCount + 1)
    @assert(alloc.sizeAlloc == beforeSize + 4096)

    let grown = cast([*] u8) req.address
    for i in 80 do
        @assert(grown[i] == cast(u8) (i + 3))

    req.mode = .Free
    req.size = 4096
    @getcontext().allocator.req(&req)
    @assert(req.address == null)
    @assert(alloc.countAlloc == beforeCount)
    @assert(alloc.sizeAlloc == beforeSize)
}

#test
{
    let alloc = defaultAllocator()
    let beforeCount = alloc.countAlloc
    let beforeSize = alloc.sizeAlloc

    var reqs: [12] AllocatorRequest
    for i in 12
    {
        reqs[i].mode = .Alloc
        reqs[i].size = 31 + cast(u64) i * 37
        if i % 3 == 0 do
            reqs[i].alignment = 64
        @getcontext().allocator.req(&reqs[i])
        @assert(reqs[i].address != null)

        let ptr = cast([*] u8) reqs[i].address
        for j in reqs[i].size do
            ptr[j] = cast(u8) ((i + j) & 0xFF)
    }

    @assert(alloc.countAlloc == beforeCount + 12)

    var assertReq: AllocatorRequest
    assertReq.mode = .AssertIsAllocated
    assertReq.address = reqs[5].address
    @getcontext().allocator.req(&assertReq)

    for i in 6
    {
        reqs[i].mode = .Free
        @getcontext().allocator.req(&reqs[i])
        @assert(reqs[i].address == null)
    }

    for i in 6 until 12
    {
        reqs[i].mode = .Realloc
        reqs[i].oldSize = reqs[i].size
        reqs[i].size += 1024
        @getcontext().allocator.req(&reqs[i])
        @assert(reqs[i].address != null)

        let ptr = cast([*] u8) reqs[i].address
        for j in reqs[i].oldSize do
            @assert(ptr[j] == cast(u8) ((i + j) & 0xFF))
    }

    for i in 6 until 12
    {
        reqs[i].mode = .Free
        @getcontext().allocator.req(&reqs[i])
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
    req.mode = .Alloc
    req.size = 64
    itf.req(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)

    scratch.release()
    @assert(scratch.block == null)
    @assert(alloc.countAlloc == 0)
    alloc.freeAll()
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
    inBuffer.mode = .Alloc
    inBuffer.size = AllocatorScratchBufSize - 64
    itf.req(&inBuffer)
    @assert(inBuffer.address != null)
    @assert(alloc.countAlloc == 1)

    var leaked: AllocatorRequest
    leaked.mode = .Alloc
    leaked.size = 256
    itf.req(&leaked)
    @assert(leaked.address != null)
    @assert(scratch.totalLeak >= 256)
    @assert(alloc.countAlloc == 2)

    leaked.mode = .Free
    itf.req(&leaked)
    @assert(leaked.address == null)
    @assert(scratch.totalLeak == 0)
    @assert(alloc.countAlloc == 1)

    scratch.release()
    @assert(alloc.countAlloc == 0)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 64
    itf.req(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)
    @assert(alloc.sizeAlloc == 64)

    let ptr = cast([*] u8) req.address
    for i in 64 do
        @assert(ptr[i] == Allocator.AllocByte)

    req.mode = .Free
    req.size = 64
    itf.req(&req)
    @assert(req.address == null)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 1)
    @assert(alloc.sizeCached >= 64)

    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 0
    itf.req(&req)
    @assert(req.address == null)

    req.mode = .Free
    req.address = null
    itf.req(&req)
    @assert(req.address == null)

    req.mode = .Realloc
    req.address = null
    req.size = 0
    itf.req(&req)
    @assert(req.address == null)

    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req1: AllocatorRequest
    req1.mode = .Alloc
    req1.size = 48
    itf.req(&req1)
    let first = req1.address

    req1.mode = .Free
    req1.size = 48
    itf.req(&req1)

    var req2: AllocatorRequest
    req2.mode = .Alloc
    req2.size = 48
    itf.req(&req2)
    @assert(req2.address == first)

    req2.mode = .Free
    req2.size = 48
    itf.req(&req2)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, electricMode: true)

    var req1: AllocatorRequest
    req1.mode = .Alloc
    req1.size = 48
    itf.req(&req1)
    let first = req1.address

    req1.mode = .Free
    req1.size = 48
    itf.req(&req1)

    var req2: AllocatorRequest
    req2.mode = .Alloc
    req2.size = 48
    itf.req(&req2)
    @assert(req2.address != first)

    req2.mode = .Free
    req2.size = 48
    itf.req(&req2)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 33
    itf.req(&req)
    let original = req.address

    let ptr = cast([*] u8) req.address
    for i in 33 do
        ptr[i] = cast(u8) (i + 1)

    req.mode = .Realloc
    req.oldSize = 33
    req.size = 48
    itf.req(&req)
    @assert(req.address == original)

    let samePtr = cast([*] u8) req.address
    for i in 33 do
        @assert(samePtr[i] == cast(u8) (i + 1))
    for i in 33 until 48 do
        @assert(samePtr[i] == Allocator.AllocByte)

    req.mode = .Free
    req.size = 48
    itf.req(&req)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 96
    itf.req(&req)
    let original = req.address
    @assert(original != null)

    let ptr = cast([*] u8) original
    for i in 96 do
        ptr[i] = cast(u8) (255 - i)

    req.mode = .Realloc
    req.oldSize = 96
    req.size = 24
    itf.req(&req)
    @assert(req.address == original)

    let shrunk = cast([*] u8) req.address
    for i in 24 do
        @assert(shrunk[i] == cast(u8) (255 - i))

    req.mode = .Realloc
    req.oldSize = 24
    req.size = 0
    itf.req(&req)
    @assert(req.address == null)

    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 24
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 24 do
        ptr[i] = cast(u8) (i * 3 + 7)

    req.mode = .Realloc
    req.oldSize = 24
    req.size = 2048
    itf.req(&req)
    @assert(req.address != null)

    let grown = cast([*] u8) req.address
    for i in 24 do
        @assert(grown[i] == cast(u8) (i * 3 + 7))

    req.mode = .Free
    req.size = 2048
    itf.req(&req)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, fillMemory: false)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = alloc.maxCachedSize + 1024
    itf.req(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeCached == 0)

    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 257
    req.alignment = 128
    itf.req(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 128 == 0)

    req.mode = .Free
    req.size = 257
    itf.req(&req)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true)
    @assert(alloc.captureAllocStack)

    var req: AllocatorRequest
    req.mode = .FreeAll
    itf.req(&req)
    @assert(req.address == null)

    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 0
    itf.req(&req)
    @assert(req.address == null)

    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1
    itf.req(&req)
    @assert(req.address != null)

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)

    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 112
    itf.req(&req)
    @assert(req.address != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header.magic == Allocator.MagicAlloc)
    @assert(header.stackCount <= @countof(header.stack))
    #if #os == Swag.TargetOs.Windows do
        if !@jit() do
            @assert(header.stackCount > 0)

    req.mode = .Free
    itf.req(&req)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, trackAllocations: true, fillMemory: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 128
    itf.req(&req)
    @assert(req.address != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header.stackCount == 0)
    @assert(alloc.firstAlloc == header)

    var assertReq: AllocatorRequest
    assertReq.mode = .AssertIsAllocated
    assertReq.address = req.address
    itf.req(&assertReq)

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)
    @assert(alloc.firstFree == header)

    let freed = alloc.userAddress(header)
    for i in 128 do
        @assert(freed[i] == Allocator.FreeByte)

    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true, trackAllocations: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 128
    itf.req(&req)
    @assert(req.address != null)
    @assert(alloc.firstAlloc != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header == alloc.firstAlloc)
    @assert(header.stackCount <= @countof(header.stack))

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)
    @assert(alloc.firstFree == header)

    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, captureStack: true, fillMemory: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 128
    itf.req(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    for i in 128 do
        @assert(ptr[i] == Allocator.AllocByte)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header.stackCount <= @countof(header.stack))

    req.mode = .Free
    itf.req(&req)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, detectLeaks: true, captureStack: true, trackAllocations: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 128
    req.hint = "debug-track-stack-no-fill"
    itf.req(&req)
    @assert(req.address != null)
    @assert(alloc.firstAlloc != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header == alloc.firstAlloc)
    @assert(header.stackCount <= @countof(header.stack))

    var assertReq: AllocatorRequest
    assertReq.mode = .AssertIsAllocated
    assertReq.address = req.address
    itf.req(&assertReq)

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, detectLeaks: true, captureStack: true, trackAllocations: true, fillMemory: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 128
    req.hint = "tracked-fill-regression"
    itf.req(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)
    @assert(alloc.firstAlloc != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header == alloc.firstAlloc)
    @assert(header.magic == Allocator.MagicAlloc)
    @assert(alloc.footer(header).magic == Allocator.MagicAlloc)
    @assert(header.stackCount <= @countof(header.stack))
    #if #os == Swag.TargetOs.Windows do
        if !@jit() do
            @assert(header.stackCount > 0)

    var assertReq: AllocatorRequest
    assertReq.mode = .AssertIsAllocated
    assertReq.address = req.address
    itf.req(&assertReq)

    req.mode = .Free
    itf.req(&req)
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
    alloc.freeAll()
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
        reqs[i].mode = .Alloc
        reqs[i].size = 64 + cast(u64) i * 17
        reqs[i].hint = "debug-mixed-regression"
        if i % 2 == 0 do
            reqs[i].alignment = 32
        itf.req(&reqs[i])
        @assert(reqs[i].address != null)
    }

    @assert(alloc.countAlloc == 10)
    alloc.checkAllMemory()

    for i in 5
    {
        reqs[i].mode = .Free
        itf.req(&reqs[i])
        @assert(reqs[i].address == null)
    }

    @assert(alloc.countAlloc == 5)
    @assert(alloc.countFree == 5)
    alloc.checkAllMemory()

    var freeAll: AllocatorRequest
    freeAll.mode = .FreeAll
    itf.req(&freeAll)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeAlloc == 0)
    @assert(alloc.sizeFree == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, detectLeaks: true, captureStack: true, trackAllocations: true, fillMemory: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 96
    req.hint = "print-leak-regression"
    itf.req(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)
    @assert(alloc.firstAlloc != null)

    alloc.printLeaks()

    var freeAll: AllocatorRequest
    freeAll.mode = .FreeAll
    itf.req(&freeAll)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.sizeAlloc == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, trackAllocations: true)

    var reqs: [4] AllocatorRequest
    for i in 4
    {
        reqs[i].mode = .Alloc
        reqs[i].size = (i + 1) * 96
        itf.req(&reqs[i])
        @assert(reqs[i].address != null)
    }

    @assert(alloc.countAlloc == 4)

    var req: AllocatorRequest
    req.mode = .FreeAll
    itf.req(&req)
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
        reqs[i].mode = .Alloc
        reqs[i].size = 32 + cast(u64) (i % 8) * 16
        itf.req(&reqs[i])
        @assert(reqs[i].address != null)

        reqs[i].mode = .Free
        itf.req(&reqs[i])
        @assert(reqs[i].address == null)
    }

    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree > 0)
    @assert(alloc.sizeCached > 0)

    var freeAll: AllocatorRequest
    freeAll.mode = .FreeAll
    itf.req(&freeAll)
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeCached == 0)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 64
    itf.req(&req)
    @assert(req.address != null)
    req.mode = .Free
    itf.req(&req)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 64
    itf.req(&req)
    @assert(req.address != null)

    req.mode = .Free
    itf.req(&req)
    @assert(alloc.countFree == 1)

    releaseAllocatorThreadCache()
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeCached == 0)
    alloc.releaseRetiredHeaps()
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, detectLeaks: true, captureStack: true, trackAllocations: true, fillMemory: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 77
    itf.req(&req)
    @assert(req.address != null)

    alloc.release()
    @assert(!alloc.installed())

    let itf2 = makeAllocator(&alloc, fillMemory: true)
    req.mode = .Alloc
    req.size = 33
    itf2.req(&req)
    @assert(req.address != null)

    req.mode = .Free
    itf2.req(&req)
    alloc.freeAll()
}

#if #os == Swag.TargetOs.Windows
{
    #test
    {
        var alloc: Allocator
        let itf = makeAllocator(&alloc)

        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = 64
        itf.req(&req)
        let first = req.address
        @assert(first != null)

        var done: s32 = 0
        var payload: AllocatorRemoteFreePayload
        payload.allocator = itf
        payload.address = first
        payload.done = &done

        var threadId: AllocatorThreadTest.DWORD
        let handle = AllocatorThreadTest.CreateThread(null, 0, &allocatorRemoteFreeThread, &payload, 0, &threadId)
        @assert(handle != null)
        discard AllocatorThreadTest.WaitForSingleObject(handle, AllocatorThreadTest.INFINITE)
        AllocatorThreadTest.CloseHandle(handle)
        @assert(@atomcmpxchg(&done, 0, 0) == 1)

        var req2: AllocatorRequest
        req2.mode = .Alloc
        req2.size = 64
        itf.req(&req2)
        @assert(req2.address == first)

        req2.mode = .Free
        req2.size = 64
        itf.req(&req2)
        alloc.freeAll()
    }

    #test
    {
        var alloc: Allocator
        let itf = makeAllocator(&alloc, detectLeaks: true, captureStack: true, trackAllocations: true, fillMemory: true)

        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = 72
        itf.req(&req)
        let first = req.address
        @assert(first != null)

        var done: s32 = 0
        var payload: AllocatorRemoteFreePayload
        payload.allocator = itf
        payload.address = first
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
        freeAll.mode = .FreeAll
        itf.req(&freeAll)
        @assert(alloc.countFree == 0)
    }
}
