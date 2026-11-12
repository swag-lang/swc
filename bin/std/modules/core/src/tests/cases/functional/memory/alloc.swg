#global if #command == Swag.CompilerCommand.Test
#global private

struct RejectAllocationAllocator {}

struct RecordingAllocationAllocator
{
    request: Swag.AllocatorRequest
    calls:   u32
    #[Swag.Align(64)]
    storage: [128] u8
}

struct ScratchOverflowAllocator
{
    calls: u32
    #[Swag.Align(16)]
    storage: [16] u8
}

struct TypedAllocationAlignmentAllocator
{
    requestedAlignment: u32
    #[Swag.Align(64)]
    storage: [256] u8
}

struct OverAlignedMemoryValue
{
    #[Swag.Align(64)]
    value: u8
}

impl Swag.IAllocator for ScratchOverflowAllocator
{
    mtd impl alloc(request: *Swag.AllocatorRequest)
    {
        .calls += 1
        if .calls == 1 do
            request.address = &.storage[0]
    }

    mtd impl realloc(request: *Swag.AllocatorRequest) { request.address = null }
    mtd impl free(_: *Swag.AllocatorRequest) {}
}

impl Swag.IAllocator for TypedAllocationAlignmentAllocator
{
    mtd impl alloc(request: *Swag.AllocatorRequest)
    {
        .requestedAlignment = request.alignment

        // Alignment zero promises only native pointer alignment. Make that path observably
        // different from the 64-byte alignment required by OverAlignedMemoryValue.
        request.address = request.alignment >= 64 ? &.storage[0] : &.storage[16]
    }

    mtd impl realloc(request: *Swag.AllocatorRequest) { request.address = null }
    mtd impl free(_: *Swag.AllocatorRequest) {}
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
    mtd impl free(_: *Swag.AllocatorRequest) {}
}

impl Swag.IAllocator for RejectAllocationAllocator
{
    mtd impl alloc(request: *Swag.AllocatorRequest) { request.address = null }

    mtd impl realloc(request: *Swag.AllocatorRequest) { request.address = null }
    mtd impl free(_: *Swag.AllocatorRequest) {}
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
    Swag.require(message.toString() == "Memory.alloc cannot allocate memory: requested size 0 bytes, alignment 32 bytes [zero request]")
}

#test
{
    let request = Swag.AllocatorRequest{size: 8192, alignment: 64, hint: "temporary arena"}
    let message = formatAllocationFailure("Memory.tempAlloc", request, false)
    Swag.require(message.toString() == "Memory.tempAlloc cannot allocate memory: requested size 8192 bytes, alignment 64 bytes [temporary arena]")
}

#test
{
    let request = Swag.AllocatorRequest{address: cast(*void?, 0x1234), size: 16384, oldSize: 4096, alignment: 128, hint: "growing texture cache"}
    let message = formatAllocationFailure("Memory.realloc", request, true)
    Swag.require(message.toString() == "Memory.realloc cannot reallocate memory: requested size 16384 bytes, old size 4096 bytes, alignment 128 bytes, address 0x1234 [growing texture cache]")
}

// An allocator that returns nothing makes the allocation panic with the complete request.
#test
{
    var reject:    RejectAllocationAllocator
    let allocator: Swag.IAllocator = &reject
    let caught = Swag.catchPanic(func|allocator|() { discard Memory.alloc(777, allocator, 32, "asset cache") })
    Swag.require(caught.raised)
    Swag.require(caught.message() == "Memory.alloc cannot allocate memory: requested size 777 bytes, alignment 32 bytes [asset cache]")
}

// A leak allocation must reject sizes whose header and alignment overhead would overflow.
#test
{
    var backing:    ScratchOverflowAllocator
    var scratch:    ScratchAllocator
    let backingItf: IAllocator = &backing
    scratch.setCapacity(1, backingItf)
    defer scratch.release()

    let scratchItf: IAllocator = &scratch
    let caught = Swag.catchPanic(func|scratchItf|()
    {
        discard Memory.alloc(Swag.U64.Max, scratchItf)
    })
    Swag.require(caught.raised)
    Swag.require(backing.calls == 1)
}

// Both explicit and context-selected custom allocators receive the complete request.
#test
{
    var recorder:  RecordingAllocationAllocator
    let allocator: Swag.IAllocator = &recorder
    let loc      = #curlocation
    let explicit = Memory.alloc(73, allocator, 32, "explicit request", loc)
    Swag.require(explicit == recorder.storage.buffer)
    Swag.require(recorder.request.size == 73 and recorder.request.alignment == 32)
    Swag.require(recorder.request.hint == "explicit request")
    Swag.require(recorder.request.callerLoc.lineStart == loc.lineStart)
    Swag.require(recorder.request.address == null and recorder.request.oldSize == 0)

    Memory.withAllocator(allocator)
    {
        let contextual = Memory.alloc(91, alignment: 64, hint: "context request", loc: loc)
        Swag.require(contextual == recorder.storage.buffer)
    }

    Swag.require(recorder.calls == 2)
    Swag.require(recorder.request.size == 91 and recorder.request.alignment == 64)
    Swag.require(recorder.request.hint == "context request")
    Swag.require(recorder.request.callerLoc.fileName == loc.fileName)
    Swag.require(recorder.request.address == null and recorder.request.oldSize == 0)
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
                let block = cast([*] u8, Memory.alloc(size, allocator, alignment))
                if alignment != 0 do
                    Swag.require(cast(u64, block) % alignment == 0)
                block[0]        = 17
                block[size - 1] = 29
                Swag.require(block[size - 1] == 29)
                Memory.free(block, size, allocator)
            }
        }
    }

    Swag.require(runtime.stats().countAlloc == 0)
}

// Typed object allocation must request enough alignment for T, even when the caller omits it.
// Before the fix, both calls pass alignment zero and receive the deliberately 16-byte-aligned slot.
#test
{
    #assert(#alignof(OverAlignedMemoryValue) == 64)

    var backing:   TypedAllocationAlignmentAllocator
    let allocator: Swag.IAllocator = &backing

    let single = Memory.new'OverAlignedMemoryValue(allocator)
    Swag.require(cast(u64, single) % 64 == 0,
                 "Memory.new<T> must honor T's alignment")
    Swag.require(backing.requestedAlignment >= 64,
                 "Memory.new<T> must request T's alignment")
}

#test
{
    #assert(#alignof(OverAlignedMemoryValue) == 64)

    var backing:   TypedAllocationAlignmentAllocator
    let allocator: Swag.IAllocator = &backing
    let items = Memory.new'OverAlignedMemoryValue(2, allocator)
    Swag.require(cast(u64, items) % 64 == 0,
                 "Memory.new<T>(count) must honor T's alignment")
    Swag.require(backing.requestedAlignment >= 64,
                 "Memory.new<T>(count) must request T's alignment")
}

// Filling and tracking are allocator diagnostics: only a runtime built with them can enable them.
#static if #hastag("Swag.AllocatorDiagnostics")
{
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
            let block = cast([*] u8, Memory.alloc(32, allocator, hint: "tracked fast allocation", loc: loc))
            for i in 32 do
                Swag.require(block[i] == Swag.Allocator.AllocByte)
            if tracked
            {
                let tracking = unwrap runtime.firstAlloc!.tracking
                Swag.require(tracking.hint == "tracked fast allocation")
                Swag.require(tracking.loc.lineStart == loc.lineStart)
            }

            Memory.free(block, 32, allocator)
            Swag.require(runtime.stats().countAlloc == 0)
        }
    }
}
