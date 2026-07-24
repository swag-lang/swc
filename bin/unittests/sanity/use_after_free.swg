#global private
using Swag

// ---------------------------------------------------------------------------
// Proven use-after-free / double-free through the language allocator interface.
// 'myFree' reaches 'IAllocator.free' with its parameter as the request address,
// which seeds its FREES summary; call sites then mark the pointer's slot and any
// later dereference (without an intervening reassignment or opaque call) is a
// proven fault. Aliases and conditional frees give misses, never reports.
// ---------------------------------------------------------------------------

// The lifecycle analysis is per-function: the helpers must force it too so their
// FREES summaries exist even in build configs where sanity is globally disabled
// (fast-compile), keeping the expected errors config-independent.
#[Swag.Sanity(.Lifecycle, true)]
func myAlloc(size: u64)->*void
{
    var req: AllocatorRequest
    req.size = size
    let allocItf = notnull @getcontext().allocator
    allocItf.alloc(&req)
    return notnull req.address
}

#[Swag.Sanity(.Lifecycle, true)]
func myFree(ptr: *void, size: u64)
{
    var req: AllocatorRequest
    req.address = ptr
    req.size    = size
    let allocItf = notnull @getcontext().allocator
    allocItf.free(&req)
}

// Read after free.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    dref p = 1
    myFree(p, 4)
    let x = dref p     // swc-expected-error {{sanity_err_use_after_free}}
    discard x
}

// Write after free.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    myFree(p, 4)
    dref p = 2     // swc-expected-error {{sanity_err_use_after_free}}
}

// Double free.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    myFree(p, 4)
    myFree(p, 4)     // swc-expected-error {{sanity_err_double_free}}
}

// Stack storage is borrowed, never allocator-owned. Passing it to free is a
// certain fault and should explain that ownership distinction at the call site.
#[Swag.Sanity(.Lifecycle, true)]
func rejectFreeBorrowed()
{
    var value: s32
    var req:   AllocatorRequest
    req.address = &value
    req.size    = #sizeof(s32)
    let allocItf = notnull @getcontext().allocator
    allocItf.free(&req)     // swc-expected-error {{sanity_err_free_borrowed}}
}

// Reassigning the pointer revalidates it.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var p = cast(*s32) myAlloc(4)
    myFree(p, 4)
    p      = cast(*s32) myAlloc(4)
    dref p = 3
    @assert(dref p == 3)
    myFree(p, 4)
}

// A conditional free never proves the fault (must-join).
#[Swag.Sanity(.Lifecycle, true)]
func useAfterConditionalFree(cond: bool)->s32
{
    let p = cast(*s32) myAlloc(4)
    dref p = 4
    if cond do
        myFree(p, 4)
    let x = dref p
    if !cond do
        myFree(p, 4)
    return x
}

// Another pointer is untouched by the free.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    let q = cast(*s32) myAlloc(4)
    dref q = 5
    myFree(p, 4)
    @assert(dref q == 5)
    myFree(q, 4)
}
