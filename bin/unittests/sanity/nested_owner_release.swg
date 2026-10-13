#global private
using Swag

// A heap-allocated carrier holds a separately allocated object in a field. Releasing that
// object, through a by-value callee, a pointer callee, or a method of the object itself,
// releases the field's pointee only: the carrier stays live for its own release afterwards.

#[Swag.NoInline]
func allocate(size: u64)->*void
{
    var req: AllocatorRequest
    req.size = size
    Swag.getContext().allocator!.alloc(&req)
    return req.address!
}

#[Swag.NoInline]
func release(ptr: *void, size: u64)
{
    var req: AllocatorRequest
    req.address = ptr
    req.size    = size
    Swag.getContext().allocator!.free(&req)
}

struct Composition { marker: s32 }
struct Context { composition: *Composition? }

// Releases what the field points to, never the context that carries the field.
#[Swag.NoInline]
func dropContext(rc: Context)
{
    if rc.composition do
        release(rc.composition, #sizeof(Composition))
}

#[Swag.NoInline]
func dropContextByPointer(rc: *Context)
{
    if rc.composition do
        release(rc.composition, #sizeof(Composition))
}

#test
{
    let context = cast(*Context, allocate(#sizeof(Context)))
    context.composition = cast(*Composition, allocate(#sizeof(Composition)))
    dropContext(context[])
    release(context, #sizeof(Context))
}

#test
{
    let context = cast(*Context, allocate(#sizeof(Context)))
    context.composition = cast(*Composition, allocate(#sizeof(Composition)))
    dropContextByPointer(context)
    release(context, #sizeof(Context))
}

// The composition releases itself through a method; the carrier stays live.
impl Composition
{
    #[Swag.NoInline]
    mtd destroy()
    {
        release(me, #sizeof(Composition))
    }
}

struct LateContext { late composition: *Composition }

#[Swag.NoInline]
func dropLateContext(rc: LateContext)
{
    rc.composition.destroy()
}

#[Swag.NoInline]
func dropAndDeleteLate(rc: *LateContext)
{
    dropLateContext(rc[])
    release(rc, #sizeof(LateContext))
}

#[Swag.NoInline]
func dropAndDelete(rc: *Context)
{
    dropContext(rc[])
    release(rc, #sizeof(Context))
}

#test
{
    let context = cast(*Context, allocate(#sizeof(Context)))
    context.composition = cast(*Composition, allocate(#sizeof(Composition)))
    dropAndDelete(context)
}

#test
{
    let context = cast(*LateContext, allocate(#sizeof(LateContext)))
    context.composition = cast(*Composition, allocate(#sizeof(Composition)))
    dropAndDeleteLate(context)
}
