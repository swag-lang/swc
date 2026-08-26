#global if #command == Swag.CompilerCommand.Test
#global private

var AllocationFailureMatched:  bool
var AllocationFailureFallback: u8

struct RejectAllocationAllocator {}

impl Swag.IAllocator for RejectAllocationAllocator
{
    mtd impl alloc(request: *Swag.AllocatorRequest)
    {
        @getcontext().user0 = cast(u64) request
        request.address     = null
    }

    mtd impl realloc(request: *Swag.AllocatorRequest) { request.address = null }
    mtd impl free(request: *Swag.AllocatorRequest) {}
    mtd impl freeAll(request: *Swag.AllocatorRequest) {}
    mtd impl assertAllocated(request: *Swag.AllocatorRequest) {}
}

func recordAllocationFailure(message: #null string, loc: Swag.SourceCodeLocation)
{
    AllocationFailureMatched = message == "Memory.alloc cannot allocate memory: requested size 777 bytes, alignment 32 bytes [asset cache]"
    let request = cast(#null *Swag.AllocatorRequest) @getcontext().user0
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
    @assert(message.toString() == "Memory.alloc cannot allocate memory: requested size 0 bytes, alignment 32 bytes [zero request]")
}

#test
{
    let request = Swag.AllocatorRequest{size: 8192, alignment: 64, hint: "temporary arena"}
    let message = formatAllocationFailure("Memory.tempAlloc", request, false)
    @assert(message.toString() == "Memory.tempAlloc cannot allocate memory: requested size 8192 bytes, alignment 64 bytes [temporary arena]")
}

#test
{
    var request: Swag.AllocatorRequest
    request.address   = cast(#null *void) 0x1234
    request.size      = 16384
    request.oldSize   = 4096
    request.alignment = 128
    request.hint      = "growing texture cache"
    let message = formatAllocationFailure("Memory.realloc", request, true)
    @assert(message.toString() == "Memory.realloc cannot reallocate memory: requested size 16384 bytes, old size 4096 bytes, alignment 128 bytes, address 0x1234 [growing texture cache]")
}

#test
{
    let cxt           = @getcontext()
    let previousPanic = cxt.panic
    let previousUser0 = cxt.user0
    defer cxt.panic = previousPanic
    defer cxt.user0 = previousUser0

    AllocationFailureMatched = false
    cxt.panic                = &recordAllocationFailure

    var reject:    RejectAllocationAllocator
    let allocator: Swag.IAllocator = &reject
    let result = Memory.alloc(777, allocator, 32, "asset cache")
    @assert(AllocationFailureMatched)
    @assert(result == &AllocationFailureFallback)
}
