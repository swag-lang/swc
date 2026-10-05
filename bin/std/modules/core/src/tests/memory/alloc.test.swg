#global if #command == Swag.CompilerCommand.Test
#global private

var AllocationFailureMatched:  bool
var AllocationFailureFallback: u8

struct RejectAllocationAllocator {}

struct RecordingAllocationAllocator
{
    request: Swag.AllocatorRequest
    calls:   u32
    #[Swag.Align(64)]
    storage: [128] u8
}

impl Swag.IAllocator for RecordingAllocationAllocator
{
    mtd impl alloc(request: *Swag.AllocatorRequest)
    {
        .request        = request[]
        .calls          += 1
        request.address = .storage.buffer
    }

    mtd impl realloc(request: *Swag.AllocatorRequest) { request.address = null }
    mtd impl free(request: *Swag.AllocatorRequest) {}
    mtd impl freeAll(request: *Swag.AllocatorRequest) {}
    mtd impl assertAllocated(request: *Swag.AllocatorRequest) {}
}

impl Swag.IAllocator for RejectAllocationAllocator
{
    mtd impl alloc(request: *Swag.AllocatorRequest)
    {
        Swag.getContext().user0 = cast(u64) request
        request.address         = null
    }

    mtd impl realloc(request: *Swag.AllocatorRequest) { request.address = null }
    mtd impl free(request: *Swag.AllocatorRequest) {}
    mtd impl freeAll(request: *Swag.AllocatorRequest) {}
    mtd impl assertAllocated(request: *Swag.AllocatorRequest) {}
}

func recordAllocationFailure(message: string?, loc: Swag.SourceCodeLocation)
{
    AllocationFailureMatched = message == "Memory.alloc cannot allocate memory: requested size 777 bytes, alignment 32 bytes [asset cache]"
    let request = cast(*Swag.AllocatorRequest?) Swag.getContext().user0
    if request do
        request.address = &AllocationFailureFallback
}

func formatAllocationFailure(operation: string, request: Swag.AllocatorRequest, includeOldAllocation: bool)->String
{
    var message: ConcatBuffer
    Memory.appendAllocationFailure(&message, operation, request, includeOldAllocation)
    return message.toString()
}

#test
{
    let request = Swag.AllocatorRequest{size: 0, alignment: 32, hint: "zero request"}
    let message = formatAllocationFailure("Memory.alloc", request, false)
    Swag.assert(message.toString() == "Memory.alloc cannot allocate memory: requested size 0 bytes, alignment 32 bytes [zero request]")
}

#test
{
    let request = Swag.AllocatorRequest{size: 8192, alignment: 64, hint: "temporary arena"}
    let message = formatAllocationFailure("Memory.tempAlloc", request, false)
    Swag.assert(message.toString() == "Memory.tempAlloc cannot allocate memory: requested size 8192 bytes, alignment 64 bytes [temporary arena]")
}

#test
{
    let request = Swag.AllocatorRequest{address: cast(*void?) 0x1234, size: 16384, oldSize: 4096, alignment: 128, hint: "growing texture cache"}
    let message = formatAllocationFailure("Memory.realloc", request, true)
    Swag.assert(message.toString() == "Memory.realloc cannot reallocate memory: requested size 16384 bytes, old size 4096 bytes, alignment 128 bytes, address 0x1234 [growing texture cache]")
}

#test
{
    let cxt = Swag.getContext()
    let previousPanic = cxt.panic
    let previousUser0 = cxt.user0
    defer cxt.panic = previousPanic
    defer cxt.user0 = previousUser0

    AllocationFailureMatched = false
    cxt.panic = &recordAllocationFailure

    var reject:    RejectAllocationAllocator
    let allocator: Swag.IAllocator = &reject
    let result = Memory.alloc(777, allocator, 32, "asset cache")
    Swag.assert(AllocationFailureMatched)
    Swag.assert(result == &AllocationFailureFallback)
}

// Both explicit and context-selected custom allocators receive the complete request.
#test
{
    var recorder:  RecordingAllocationAllocator
    let allocator: Swag.IAllocator = &recorder
    let loc      = #curlocation
    let explicit = Memory.alloc(73, allocator, 32, "explicit request", loc)
    Swag.assert(explicit == recorder.storage.buffer)
    Swag.assert(recorder.request.size == 73 and recorder.request.alignment == 32)
    Swag.assert(recorder.request.hint == "explicit request")
    Swag.assert(recorder.request.callerLoc.lineStart == loc.lineStart)
    Swag.assert(recorder.request.address == null and recorder.request.oldSize == 0)

    Memory.withAllocator(allocator)
    {
        let contextual = Memory.alloc(91, alignment: 64, hint: "context request", loc: loc)
        Swag.assert(contextual == recorder.storage.buffer)
    }

    Swag.assert(recorder.calls == 2)
    Swag.assert(recorder.request.size == 91 and recorder.request.alignment == 64)
    Swag.assert(recorder.request.hint == "context request")
    Swag.assert(recorder.request.callerLoc.fileName == loc.fileName)
    Swag.assert(recorder.request.address == null and recorder.request.oldSize == 0)
}

// Reusing a current page and falling back for a larger size or alignment share the same contract.
#test
{
    var runtime: Swag.Allocator
    runtime.setup()
    defer runtime.releaseAll()
    let allocator: Swag.IAllocator = &runtime
    for size in [1'u64, 8, 16, 32, 500, 65536, 131072]
    {
        for alignment in [0'u32, 8, 16, 32, 256]
        {
            for 2
            {
                let block = cast([*] u8) Memory.alloc(size, allocator, alignment)
                if alignment != 0 do
                    Swag.assert(cast(u64) block % alignment == 0)
                block[0]        = 17
                block[size - 1] = 29
                Swag.assert(block[size - 1] == 29)
                Memory.free(block, size, allocator)
            }
        }
    }

    Swag.assert(runtime.stats().countAlloc == 0)
}

// A warm page cannot bypass filling or tracking when those modes are enabled later.
#test
{
    for tracked in [false, true]
    {
        var runtime: Swag.Allocator
        runtime.setup()
        defer runtime.releaseAll()
        let allocator: Swag.IAllocator = &runtime
        let warm = Memory.alloc(32, allocator)
        Memory.free(warm, 32, allocator)
        runtime.configure(false, true, false, tracked, true)

        let loc   = #curlocation
        let block = cast([*] u8) Memory.alloc(32, allocator, hint: "tracked fast allocation", loc: loc)
        for i in 32 do
            Swag.assert(block[i] == Swag.Allocator.AllocByte)
        if tracked
        {
            let tracking = runtime.firstAlloc!.tracking!
            Swag.assert(tracking.hint == "tracked fast allocation")
            Swag.assert(tracking.loc.lineStart == loc.lineStart)
        }

        Memory.free(block, 32, allocator)
        Swag.assert(runtime.stats().countAlloc == 0)
    }
}
