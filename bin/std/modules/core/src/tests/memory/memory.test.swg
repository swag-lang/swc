#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertBytesEqual(lhs, rhs: const [..] u8)->bool
{
    if @countof(lhs) != @countof(rhs) do
        return false

    foreach value, index in lhs
    {
        if value != rhs[index] do
            return false
    }

    return true
}

func pushAllocatorAcceptsNull()->bool
{
    Memory.pushAllocator(null)
    {
        return @getcontext().allocator == null
    }

    return false
}

func makeFastAllocator(alloc: *Memory.FastAllocator, sys: *SystemAllocator)->IAllocator
{
    let sysItf = @mkinterface(sys, #typeof(dref sys), IAllocator)
    alloc.setup(sysItf)
    alloc.detectLeaks = false
    alloc.captureAllocStack = false
    return @mkinterface(alloc, #typeof(dref alloc), IAllocator)
}

#if WINDOWS
{
    struct FastAllocatorRemoteFreePayload
    {
        allocator: IAllocator
        address:   *void
        done:      *s32
    }

    func fastAllocatorRemoteFreeThread(th: Threading.Thread)
    {
        let payload = cast(*FastAllocatorRemoteFreePayload) th.userParam

        var req: AllocatorRequest
        req.mode = .Free
        req.address = payload.address
        req.size = 64
        payload.allocator.req(&req)

        Atomic.add(payload.done, 1)
    }
}

#test
{
    var src: [4] u8 = [1, 2, 3, 4]
    var dst: [4] u8

    Memory.copy(@dataof(dst), @dataof(src), #sizeof(src))
    @assert(assertBytesEqual(dst, src))
    @assert(Memory.compare(@dataof(dst), @dataof(src), #sizeof(src)) == 0)

    Memory.set(@dataof(dst), 0xAB, #sizeof(dst))
    let filled: [4] u8 = [0xAB, 0xAB, 0xAB, 0xAB]
    @assert(assertBytesEqual(dst, filled))

    Memory.clear(@dataof(dst), #sizeof(dst))
    let zeroed: [4] u8 = [0, 0, 0, 0]
    @assert(assertBytesEqual(dst, zeroed))
    @assert(Memory.equals(&dst, &zeroed))
}

#test
{
    @assert(Memory.align(13, 8) == 16)
    @assert(Memory.align(16, 8) == 16)
    @assert(Memory.align(17, 4) == 20)
    @assert(Memory.align(13, 0) == #sizeof(*void) * 2)

    var buffer: [32] u8
    let misaligned = cast([*] u8) @dataof(buffer) + 1
    @assert(cast(u64) misaligned == cast(u64) @dataof(buffer) + 1)
    let alignedValue = Memory.align(cast(u64) misaligned, 8)
    let aligned = Memory.align(misaligned, 8)
    @assert(cast(u64) aligned % 8 == 0)
    @assert(cast(u64) aligned == alignedValue)
    @assert(cast(u64) aligned >= cast(u64) misaligned)
}

#test
{
    @assert(@getcontext().allocator != null)
    @assert(pushAllocatorAcceptsNull())
    @assert(@getcontext().allocator != null)
}

#test
{
    var sys: SystemAllocator
    var alloc: Memory.FastAllocator
    let itf = makeFastAllocator(&alloc, &sys)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 64
    itf.req(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)
    @assert(alloc.sizeAlloc == 64)

    let ptr = cast([*] u8) req.address
    for i in 64 do
        @assert(ptr[i] == Memory.FastAllocator.AllocByte)

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
    var sys: SystemAllocator
    var alloc: Memory.FastAllocator
    let itf = makeFastAllocator(&alloc, &sys)

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
    var sys: SystemAllocator
    var alloc: Memory.FastAllocator
    alloc.electricMode = true
    let itf = makeFastAllocator(&alloc, &sys)

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
    var sys: SystemAllocator
    var alloc: Memory.FastAllocator
    let itf = makeFastAllocator(&alloc, &sys)

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
        @assert(samePtr[i] == Memory.FastAllocator.AllocByte)

    req.mode = .Free
    req.size = 48
    itf.req(&req)
    alloc.freeAll()
}

#test
{
    var sys: SystemAllocator
    var alloc: Memory.FastAllocator
    let itf = makeFastAllocator(&alloc, &sys)

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
    var sys: SystemAllocator
    var alloc: Memory.FastAllocator
    let itf = makeFastAllocator(&alloc, &sys)

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
    var sys: SystemAllocator
    var alloc: Memory.FastAllocator
    alloc.trackAllocations = true
    let itf = makeFastAllocator(&alloc, &sys)

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
    let previous = @getcontext().allocator
    let installed = Memory.installFastAllocator(electricMode: true, detectLeaks: false, captureStack: false)
    defer @getcontext().allocator = previous

    @assert(installed == Memory.defaultFastAllocator())
    @assert(installed.electricMode)
    @assert(@getcontext().allocator != previous)

    let ptr = Memory.alloc(32, hint: "fast allocator install")
    @assert(ptr != null)
    Memory.free(ptr, 32, hint: "fast allocator install")
}

#if WINDOWS
{
    #test
    {
        var sys: SystemAllocator
        var alloc: Memory.FastAllocator
        let itf = makeFastAllocator(&alloc, &sys)

        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = 64
        itf.req(&req)
        let first = req.address
        @assert(first != null)

        var done: s32 = 0
        var payload: FastAllocatorRemoteFreePayload
        payload.allocator = itf
        payload.address = first
        payload.done = &done

        var thread: Threading.Thread
        discard catch thread.init(&fastAllocatorRemoteFreeThread, &payload)
        @assert(@err == null)
        discard catch thread.start()
        @assert(@err == null)
        thread.wait()
        @assert(Atomic.get(&done) == 1)

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
}
