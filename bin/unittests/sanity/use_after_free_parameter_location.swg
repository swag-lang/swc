#global private
using Swag

#[Swag.Sanity(.Lifecycle, true)]
#[Swag.NoInline]
func heapAlloc(size: u64)->*void
{
    var req: AllocatorRequest
    req.size = size
    let itf = Swag.getContext().allocator!
    itf.alloc(&req)
    return req.address!
}

#[Swag.Sanity(.Lifecycle, true)]
#[Swag.NoInline]
func heapFree(ptr: *void, size: u64)
{
    var req: AllocatorRequest
    req.address = ptr
    req.size    = size
    let itf = Swag.getContext().allocator!
    itf.free(&req)
}

struct Node { first, second: s32 }

// Inlining homes the call result once. Later accesses must name the use in the
// inlined body, even though runtime safety did not request the home.
#[Swag.Sanity(.Lifecycle, true)]
#[Swag.Inline]
func destroyThenTouch(node: *Node)
{
    heapFree(node, 8)     // swc-expected-note {{sanity_note_pointer_released_here}}
    node.first = 0        // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    destroyThenTouch(cast(*Node) heapAlloc(8))
}
