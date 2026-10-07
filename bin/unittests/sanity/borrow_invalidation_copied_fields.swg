#global private
using Swag

// Moving cache entries leaves copied pointers valid, while pointers to their slots
// still become stale. Opaque accessors must preserve that distinction.

struct BorrowFieldEntry { value: *s32?; marker: s32 }
struct BorrowFieldCache
{
    data:     [*] BorrowFieldEntry?
    capacity: u64
}
impl BorrowFieldCache
{
    mtd opDrop()
    {
        if .data
        {
            var request: AllocatorRequest
            request.address = .data
            request.size    = .capacity * #sizeof(BorrowFieldEntry)
            Swag.getContext().allocator!.free(&request)
        }
    }

    #[Swag.NoInline]
    mtd reserve(count: u64)
    {
        var request: AllocatorRequest
        request.address = .data
        request.oldSize = .capacity * #sizeof(BorrowFieldEntry)
        request.size    = count * #sizeof(BorrowFieldEntry)
        Swag.getContext().allocator!.realloc(&request)
        .data     = cast(request.address)
        .capacity = count
    }

    #[Swag.NoInline]
    mtd set(value: *s32) { .data![0].value = value; .data[0].marker = 7 }

    #[Swag.NoInline]
    mtd entry()->*BorrowFieldEntry? => &.data![0]

    #[Swag.NoInline]
    mtd get()->*s32?
    {
        let found = .entry()
        if found do return found.value
        return null
    }
}

#test
{
    var value = 33
    var cache: BorrowFieldCache
    cache.reserve(1)
    cache.set(&value)
    let first = cache.get()
    cache.reserve(2)
    Swag.assert(first == &value and first![] == 33)
}

#[Swag.NoInline]
func borrowFieldIdentity(value: *s32?)->*s32? => value

#test
{
    var value = 41
    var cache: BorrowFieldCache
    cache.reserve(1)
    cache.set(&value)
    let entry     = cache.entry()!
    let copied    = entry.value
    let forwarded = borrowFieldIdentity(entry.value)
    cache.reserve(2)
    Swag.assert(copied == &value and forwarded == &value)
    Swag.assert(copied![] == 41 and forwarded![] == 41)
}

// Copying a field must not change the original accessor snapshot shared by entry.
func borrowFieldRejectEntry(cache: *BorrowFieldCache)->s32
{
    let entry  = cache.entry()!
    let copied = entry.value
    Swag.assert(copied != null)
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return entry.marker
}

func borrowFieldRejectForwardedSlot(cache: *BorrowFieldCache)->s32
{
    let entry = cache.entry()!
    let slot  = borrowFieldIdentity(&entry.marker)
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return slot![]
}

#[Swag.NoInline]
func borrowFieldCacheIdentity(cache: *BorrowFieldCache)->*BorrowFieldCache => cache

// The accessor can sit between storage-preserving calls on either side.
func borrowFieldRejectForwardedOwner(cache: *BorrowFieldCache)->s32
{
    let entry = borrowFieldCacheIdentity(cache).entry()!
    let slot  = borrowFieldIdentity(&entry.marker)
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return slot![]
}

struct BorrowFieldView { data: [*] BorrowFieldEntry? }
impl BorrowFieldCache
{
    #[Swag.NoInline]
    mtd view()->BorrowFieldView
    {
        var result: BorrowFieldView
        result.data = .data
        return result
    }
}

// A copied aggregate can still contain a view into the owner's allocation.
func borrowFieldRejectView(cache: *BorrowFieldCache)->s32
{
    let view = cache.view()
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view.data![0].marker
}

func borrowFieldRejectViewField(cache: *BorrowFieldCache)->s32
{
    let view = cache.view()
    let data = view.data
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return data![0].marker
}

func borrowFieldRejectDirectViewField(cache: *BorrowFieldCache)->s32
{
    let data = cache.view().data
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return data![0].marker
}

func borrowFieldRejectLocalViewField()->s32
{
    var cache: BorrowFieldCache
    cache.reserve(1)
    let view = cache.view()
    let data = view.data
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return data![0].marker
}

func borrowFieldRejectAliasedViewField(cache: *BorrowFieldCache)->s32
{
    let view    = cache.view()
    let viewPtr = &view
    let data    = viewPtr.data
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return data![0].marker
}

struct BorrowFieldNestedView { view: BorrowFieldView }
impl BorrowFieldCache
{
    #[Swag.NoInline]
    mtd nestedView()->BorrowFieldNestedView => {.view()}
}

func borrowFieldRejectNestedView(cache: *BorrowFieldCache)->s32
{
    let returned = cache.nestedView()
    let view     = returned.view
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view.data![0].marker
}

func borrowFieldRejectDirectNestedView(cache: *BorrowFieldCache)->s32
{
    let view = cache.nestedView().view
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view.data![0].marker
}

func borrowFieldRejectCopyFirst(cache: *BorrowFieldCache, chooseSlot: bool)->s32
{
    let entry   = cache.entry()!
    var pointer = entry.value
    if chooseSlot do pointer = &entry.marker
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return pointer![]
}

func borrowFieldRejectSlotFirst(cache: *BorrowFieldCache, chooseCopy: bool)->s32
{
    let entry = cache.entry()!
    var pointer: *s32? = &entry.marker
    if chooseCopy do pointer = entry.value
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return pointer![]
}

#[Swag.NoInline]
func borrowFieldSelect(cache: *BorrowFieldCache, chooseSlot: bool)->*s32?
{
    let entry = cache.entry()!
    if chooseSlot do return &entry.marker
    return entry.value
}

func borrowFieldRejectSelectedSlot(cache: *BorrowFieldCache, chooseSlot: bool)->s32
{
    let pointer = borrowFieldSelect(cache, chooseSlot)
    cache.reserve(2)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return pointer![]
}

// The unknown copied field still carries its original conservative lifetime bound.
func borrowFieldRejectEscapingLocal()->*s32?
{
    var value = 53
    var cache: BorrowFieldCache
    cache.reserve(1)
    cache.set(&value)
    return borrowFieldIdentity(cache.get())     // swc-expected-error {{sanity_err_borrow_escape}}
}
