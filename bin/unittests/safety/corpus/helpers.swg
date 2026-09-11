#global namespace Corpus

using Swag

// -----------------------------------------------------------------------------
// Shared support for the CWE corpus.
//
// Every helper here exists for one reason: to defeat constant folding, so a case meant for
// a RUNTIME guard is not answered by the static analysis instead, and the reverse. A corpus
// that cannot say which layer caught a fault measures nothing.
// -----------------------------------------------------------------------------

// Launders a value through a call the optimizer must not see into.
#[Swag.NoInline]
func opaqueU64(v: u64)->u64 => v

#[Swag.NoInline]
func opaqueS64(v: s64)->s64 => v

#[Swag.NoInline]
func opaqueS32(v: s32)->s32 => v

#[Swag.NoInline]
func opaqueU32(v: u32)->u32 => v

#[Swag.NoInline]
func opaqueS8(v: s8)->s8 => v

#[Swag.NoInline]
func opaqueU8(v: u8)->u8 => v

#[Swag.NoInline]
func opaqueS16(v: s16)->s16 => v

#[Swag.NoInline]
func opaqueF32(v: f32)->f32 => v

#[Swag.NoInline]
func opaqueBool(v: bool)->bool => v

// -----------------------------------------------------------------------------
// The heap, reached through the language interface rather than through a standard module:
// the corpus exercises what the LANGUAGE knows, not what a name in 'std' happens to be
// called. These two are what seed the FREES summary the lifetime analysis reads.
// -----------------------------------------------------------------------------

#[Swag.Sanity(.Lifecycle, true)]
func heapAlloc(size: u64)->*void
{
    var req: AllocatorRequest
    req.size = size
    let itf = Swag.getContext().allocator!
    itf.alloc(&req)
    return req.address!
}

#[Swag.Sanity(.Lifecycle, true)]
func heapFree(ptr: *void, size: u64)
{
    var req: AllocatorRequest
    req.address = ptr
    req.size    = size
    let itf = Swag.getContext().allocator!
    itf.free(&req)
}

// Retain physical storage until the probe ends. Known static misses can then execute
// their release paths without a leak or a second real free in the compiler's heap.
// Logical releases remain observable, including a second release of the same block.
struct RetainedHeap
{
    late base:  IAllocator
    requests:   [4] AllocatorRequest
    released:   [4] bool
    count:      u64
    frees:      u64
    duplicates: u64
}

impl RetainedHeap
{
    mtd const liveCount()->u64
    {
        var result = 0'u64
        for index in .count
        {
            if not .released[index] do result += 1
        }
        return result
    }

    mtd opDrop()
    {
        for index in .count do .base.free(&.requests[index])
    }
}

impl IAllocator for RetainedHeap
{
    mtd impl alloc(request: *AllocatorRequest)
    {
        Swag.assert(.count < .requests.count)
        .base.alloc(request)
        .requests[.count] = request[]
        .count += 1
    }

    mtd impl free(request: *AllocatorRequest)
    {
        for index in .count
        {
            if .requests[index].address != request.address do continue
            .frees += 1
            if .released[index] do .duplicates += 1
            .released[index] = true
            return
        }
        Swag.assert(false)
    }

    // These probes exercise alloc/free only. An unexpected operation must fail the test.
    mtd impl realloc(request: *AllocatorRequest) { discard request; Swag.assert(false) }
    mtd impl freeAll(request: *AllocatorRequest) { discard request; Swag.assert(false) }
    mtd impl assertAllocated(request: *AllocatorRequest) { discard request; Swag.assert(false) }
}
