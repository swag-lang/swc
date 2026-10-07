#global private
using Swag

// ---------------------------------------------------------------------------
// A helper handed the address of a pointer - a field, a local - can release the
// object that pointer designates and empty the box. What it frees is the box's
// CONTENT: the box, and the object or frame holding it, stay alive. Copies of
// the released pointer kept elsewhere are dead, and freeing the box itself is
// still a release of whatever storage the caller passed.
// ---------------------------------------------------------------------------

struct BoxItem
{
    value: s32
}

struct BoxOwner
{
    item:  *BoxItem?
    count: s32
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func boxAlloc(size: u64)->*void
{
    var request: AllocatorRequest
    request.size = size
    Swag.getContext().allocator!.alloc(&request)
    return request.address!
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func boxFree(pointer: *void, size: u64)
{
    var request: AllocatorRequest
    request.address = pointer
    request.size    = size
    Swag.getContext().allocator!.free(&request)
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func boxNewItem()->*BoxItem => cast(*BoxItem, boxAlloc(#sizeof(BoxItem)))

// Releases the item the box holds, then empties the box.
#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func boxStop(box: *(*BoxItem?))
{
    if let item = box[]
    {
        boxFree(item, #sizeof(BoxItem))
        box[] = null
    }
}

impl BoxOwner
{
    // The same release, read straight through the box.
    #[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
    mtd stop(field: *(*BoxItem?))
    {
        if field[] do
            boxFree(field[]!, #sizeof(BoxItem))
        field[] = null
    }

    #[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
    mtd finish()
    {
        .stop(&.item)
    }
}

// A field box: the object holding the field outlives the release.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let owner = cast(*BoxOwner, boxAlloc(#sizeof(BoxOwner)))
    owner.item = boxNewItem()
    owner.finish()
    owner.count = 1
    Swag.assert(owner.count == 1)
    Swag.assert(owner.item == null)

    owner.item = boxNewItem()
    boxStop(&owner.item)
    owner.count = 2
    Swag.assert(owner.count == 2)
    Swag.assert(owner.item == null)
    boxFree(owner, #sizeof(BoxOwner))
}

// A local box: the local is frame storage, but only what it holds is released.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var item: *BoxItem? = boxNewItem()
    boxStop(&item)
    Swag.assert(item == null)

    var owner: BoxOwner
    owner.item = boxNewItem()
    owner.finish()
    owner.count = 3
    Swag.assert(owner.count == 3)
    Swag.assert(owner.item == null)
}

// A copy of the pointer the box held is released with it.
#[Swag.Sanity(.Lifecycle, true)]
func boxReadOldCopy()->s32
{
    let item = boxNewItem()
    item.value = 4
    var box: *BoxItem? = item
    boxStop(&box)         // swc-expected-note {{sanity_note_pointer_released_here}}
    return item.value     // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    discard boxReadOldCopy()
}

// Releasing the box itself still releases the storage the caller passed.
#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func boxFreeBox(box: *(*BoxItem?))
{
    boxFree(box, #sizeof(*BoxItem))
}

#[Swag.Sanity(.Lifecycle, true)]
func boxFreeLocalBox()
{
    var box: *BoxItem? = null     // swc-expected-note {{sema_note_borrow_source_declared_here}}
    boxFreeBox(&box)              // swc-expected-error {{sanity_err_free_borrowed}}
}
