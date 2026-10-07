#global private

struct HeapFieldAddressEntry
{
    value: s32
}

struct HeapFieldAddressTable
{
    entries: [*] HeapFieldAddressEntry?
}

impl HeapFieldAddressTable
{
    #[Swag.NoInline]
    mtd valueAddr()->*s32
    {
        let slots = .entries!
        return &slots[0].value
    }
}

var heapFieldAddressSaved: *s32?

#test
{
    var request: Swag.AllocatorRequest
    request.size = #sizeof(HeapFieldAddressEntry)
    let allocator = Swag.getContext().allocator!
    allocator.alloc(&request)
    defer allocator.free(&request)

    var table: HeapFieldAddressTable
    table.entries          = cast([*] HeapFieldAddressEntry, request.address!)
    table.entries[0].value = 41
    heapFieldAddressSaved  = table.valueAddr()
    Swag.assert(heapFieldAddressSaved![] == 41)
    heapFieldAddressSaved = null
}

// The same projection must keep the borrow when the stored pointer names a local.
func heapFieldAddressRejectLocal()
{
    var entry: HeapFieldAddressEntry
    var table: HeapFieldAddressTable
    table.entries         = cast([*] HeapFieldAddressEntry, &entry)
    heapFieldAddressSaved = table.valueAddr()     // swc-expected-error {{sanity_err_borrow_escape}}
}
