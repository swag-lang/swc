#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    Swag.assert(Memory.align(17'u64, 16) == 32)
    Swag.assert(Memory.align(32'u64, 16) == 32)
    Swag.assert(Memory.align(17'u64, 0) == 24)
}

struct RequestRecorder
{
    #[Swag.Align(64)]
    storage:     [64] u8
    last:        Swag.AllocatorRequest
    allocations: u32
    frees:       u32
}

impl Swag.IAllocator for RequestRecorder
{
    mtd impl alloc(request: *Swag.AllocatorRequest)
    {
        .last           = request[]
        .allocations    += 1
        request.address = &.storage
    }

    mtd impl free(request: *Swag.AllocatorRequest)
    {
        .last  = request[]
        .frees += 1
        request.address = null
    }

    mtd impl realloc(?: *Swag.AllocatorRequest) {}
    mtd impl freeAll(?: *Swag.AllocatorRequest) {}
    mtd impl assertAllocated(?: *Swag.AllocatorRequest) {}
}

// Allocation wrappers must keep the request and allocator selection intact
// when called from a module that imports core's generated API.
#test
{
    var contextRecorder:  RequestRecorder
    var explicitRecorder: RequestRecorder
    let previous = Swag.getContext()
    var context  = previous[]
    context.allocator = &contextRecorder
    Swag.setContext(&context)
    defer Swag.setContext(previous)

    let fromContext = Memory.alloc(17, alignment: 16, hint: "context allocation")
    Swag.assert(fromContext == cast([*] void, &contextRecorder.storage))
    Swag.assert(contextRecorder.allocations == 1)
    Swag.assert(contextRecorder.last.size == 17)
    Swag.assert(contextRecorder.last.alignment == 16)
    Swag.assert(contextRecorder.last.hint == "context allocation")
    Swag.assert(contextRecorder.last.address == null)
    Swag.assert(contextRecorder.last.oldSize == 0)
    Swag.assert(contextRecorder.last.callerLoc.fileName == #curlocation.fileName)

    let explicit: Swag.IAllocator = &explicitRecorder
    let fromExplicit = Memory.alloc(33, explicit, 32, "explicit allocation")
    Swag.assert(fromExplicit == cast([*] void, &explicitRecorder.storage))
    Swag.assert(contextRecorder.allocations == 1)
    Swag.assert(explicitRecorder.allocations == 1)
    Swag.assert(explicitRecorder.last.size == 33)
    Swag.assert(explicitRecorder.last.alignment == 32)
    Swag.assert(explicitRecorder.last.hint == "explicit allocation")

    Memory.free(fromContext, 17, hint: "context free")
    Memory.free(fromExplicit, 33, explicit, "explicit free")
    Memory.free(null, 0, explicit)
    Swag.assert(contextRecorder.frees == 1)
    Swag.assert(contextRecorder.last.address == fromContext)
    Swag.assert(contextRecorder.last.size == 17)
    Swag.assert(contextRecorder.last.hint == "context free")
    Swag.assert(explicitRecorder.frees == 1)
    Swag.assert(explicitRecorder.last.address == fromExplicit)
    Swag.assert(explicitRecorder.last.size == 33)
    Swag.assert(explicitRecorder.last.hint == "explicit free")
}
