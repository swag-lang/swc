#global private
using Swag

struct Holder
{
    buffer: *void
}

#[Swag.NoInline]
func opaqueHolder(holder: *Holder)->*Holder => holder

#[Swag.NoInline]
func allocate(size: u64)->*void
{
    var request: AllocatorRequest
    request.size = size
    Swag.getContext().allocator!.alloc(&request)
    return request.address!
}

#[Swag.Inline]
func release(address: *void?, size: u64)
{
    if not address do return
    var request: AllocatorRequest
    request.address = address
    request.size    = size
    Swag.getContext().allocator!.free(&request)
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let value = cast(*u32, allocate(4))
    let same  = value
    release(value, 4)            // swc-expected-note {{sanity_note_pointer_released_here}}
    Swag.assert(same[] == 7)     // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let value = allocate(4)
    release(value, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    release(value, 4)     // swc-expected-error {{sanity_err_double_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var value = cast(*u32, allocate(4))
    release(value, 4)
    value   = cast(*u32, allocate(4))
    value[] = 7
    Swag.assert(value[] == 7)
    release(value, 4)
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseParameter(value: *u32)
{
    release(value, 4)             // swc-expected-note {{sanity_note_pointer_released_here}}
    Swag.assert(value[] == 7)     // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    releaseParameter(cast(*u32, allocate(4)))
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var holder = Holder{allocate(4)}
    release(holder.buffer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    let buffer = cast(*u32, holder.buffer)
    Swag.assert(buffer[] == 7)     // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var local  = Holder{allocate(4)}
    let holder = opaqueHolder(&local)
    release(holder.buffer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    let buffer = cast(*u32, holder.buffer)
    Swag.assert(buffer[] == 7)     // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var local  = Holder{allocate(4)}
    let holder = opaqueHolder(&local)
    release(holder.buffer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    release(holder.buffer, 4)     // swc-expected-error {{sanity_err_double_free}}
}

// A null release and replacement of the request's pointer remain valid.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    release(null, 0)
    let first  = allocate(4)
    let second = allocate(4)
    var request: AllocatorRequest
    request.address = first
    request.size    = 4
    let allocator = Swag.getContext().allocator!
    var empty: AllocatorRequest
    allocator.free(&empty)
    allocator.free(&empty)
    allocator.free(&request)
    request.address = second
    allocator.free(&request)
}

#[Swag.NoInline]
func replaceBuffer(buffer: **void, replacement: *void)
{
    buffer[] = replacement
}

#[Swag.NoInline]
func opaqueIndex()->u64 => 0

#[Swag.Inline]
func releaseAndReplaceIndexed(holder: *Holder, replacement: *void, index: u64)
{
    var request: AllocatorRequest
    request.address = holder.buffer
    request.size    = 4
    cast([*] *void, holder)[index] = replacement
    Swag.getContext().allocator!.free(&request)
}

#[Swag.Inline]
func releaseAndReplace(holder: *Holder, replacement: *void, indirect: bool)
{
    var request: AllocatorRequest
    request.address = holder.buffer
    request.size    = 4
    if indirect do
        replaceBuffer(&holder.buffer, replacement)
    else do
        holder.buffer = replacement
    Swag.getContext().allocator!.free(&request)
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var local  = Holder{allocate(4)}
    let holder = opaqueHolder(&local)
    releaseAndReplace(holder, allocate(4), false)
    let first = cast(*u32, holder.buffer)
    first[] = 7
    Swag.assert(first[] == 7)
    releaseAndReplace(holder, allocate(4), true)
    let second = cast(*u32, holder.buffer)
    second[] = 8
    Swag.assert(second[] == 8)
    releaseAndReplaceIndexed(holder, allocate(4), opaqueIndex())
    let third = cast(*u32, holder.buffer)
    third[] = 9
    Swag.assert(third[] == 9)
    release(third, 4)
}
