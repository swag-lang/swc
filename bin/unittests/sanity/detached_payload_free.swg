#global private
using Swag

// ---------------------------------------------------------------------------
// A container that releases the payload it just replaced is reallocating itself,
// not freeing its receiver. 'old = .table; .table = alloc(...); free(old)' is the
// shape of HashTable.reserve: the replacement detaches 'old' from the owner's new
// allocation (so a view taken before the growth is not invalidated twice), but what
// 'old' addresses is still memory the owner released. Handing it to a freeing callee
// must not summarize 'reserve' as freeing 'me': that summary chained through every
// method touching the container, and two such calls in a row on the same heap
// object were reported as a double free.
// ---------------------------------------------------------------------------

#[Swag.Sanity(.Lifecycle, true)]
func myAlloc(size: u64)->*void
{
    var req: AllocatorRequest
    req.size = size
    let allocItf = Swag.getContext().allocator!
    allocItf.alloc(&req)
    return req.address!
}

#[Swag.Sanity(.Lifecycle, true)]
func myFree(ptr: *void, size: u64)
{
    var req: AllocatorRequest
    req.address = ptr
    req.size    = size
    let allocItf = Swag.getContext().allocator!
    allocItf.free(&req)
}

struct DetachedTable
{
    table:    [*] u64?
    capacity: u64
}

impl DetachedTable
{
    #[Swag.Sanity(.Lifecycle, true)]
    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return

        let old      = .table
        let oldBytes = .capacity * #sizeof(u64)
        .table    = cast([*] u64) myAlloc(newCapacity * #sizeof(u64))
        .capacity = newCapacity
        if old != null do
            myFree(cast(*void) old!, oldBytes)
    }

    #[Swag.Sanity(.Lifecycle, true)]
    mtd add(value: u64)
    {
        .reserve(.capacity + 1)
        .table![.capacity - 1] = value
    }

    // A view into the payload, and a growth that hands the new view back.
    #[Swag.Sanity(.Lifecycle, true)]
    mtd entry(index: u64)->*u64
    {
        return &.table![index]
    }

    #[Swag.Sanity(.Lifecycle, true)]
    mtd addEntry(value: u64)->*u64
    {
        .add(value)
        return &.table![.capacity - 1]
    }

    mtd opDrop()
    {
        if .table != null do
            myFree(cast(*void) .table!, .capacity * #sizeof(u64))
    }
}

struct DetachedOwner
{
    items: DetachedTable
}

impl DetachedOwner
{
    #[Swag.Sanity(.Lifecycle, true)]
    mtd setState(value: u64)
    {
        .items.add(value)
    }

    #[Swag.Sanity(.Lifecycle, true)]
    mtd setStatus(value: u64)
    {
        .items.add(value)
    }
}

#[Swag.Sanity(.Lifecycle, true)]
func newOwner()->*DetachedOwner
{
    let owner = cast(*DetachedOwner) myAlloc(#sizeof(DetachedOwner))
    owner.items.table    = null
    owner.items.capacity = 0
    return owner
}

#[Swag.Sanity(.Lifecycle, true)]
func deleteOwner(owner: *DetachedOwner)
{
    Swag.drop(&owner.items)
    myFree(cast(*void) owner, #sizeof(DetachedOwner))
}

// Two consecutive calls that grow the embedded container of one heap object:
// neither frees the owner, so the second is not a double free.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let owner = newOwner()
    owner.setState(1)
    owner.setStatus(2)
    Swag.assert(owner.items.capacity == 2)
    Swag.assert(owner.items.table![1] == 2)
    deleteOwner(owner)
}

// The view is refreshed by the very assignment the growth is evaluated for: what is
// read afterwards is the entry 'addEntry' handed back, never the stale one.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let owner = newOwner()
    owner.setState(1)
    var view = owner.items.entry(0)
    Swag.assert(view[] == 1)
    view = owner.items.addEntry(3)
    Swag.assert(view[] == 3)
    deleteOwner(owner)
}
