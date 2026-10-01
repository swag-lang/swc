#global public

// Borrow summaries must cross the module boundary through the generated API
// ('Swag.BorrowSummary'): consumed by 'consumer_exe'.
var depBorrowGlobalInt:   s32 = 7
var depBorrowGlobalStash: *s32?

// Return summary: the result borrows the parameter.
func depBorrowPassthrough(p: *s32)->*s32
{
    return p
}

// Transitive return summary through a wrapper.
func depBorrowWrap(p: *s32)->*s32
{
    return depBorrowPassthrough(p)
}

// Stores summary: the parameter is kept beyond the call.
func depBorrowStash(p: *s32)
{
    depBorrowGlobalStash = p
}

// Globals are not exported in the generated API: read the stash through a function.
func depBorrowStashed()->*s32?
{
    return depBorrowGlobalStash
}

// No retention: the pointer is borrowed only for this call.
func depBorrowRead(p: *s32)->s32
{
    return p[]
}

// Every parameter carried by an aggregate contributes to the exported return summary.
struct DepBorrowPair
{
    public
    {
        first:  *s32
        second: *s32
    }
}

func depBorrowMakePair(first, second: *s32)->DepBorrowPair
{
    return {first, second}
}

// Pair summary: the item is stored into storage reachable from 'me'.
struct DepBorrowContainer
{
    public slot: *s32?
}

impl DepBorrowContainer
{
    mtd add(item: *s32)
    {
        .slot = item
    }
}

// A separately allocated carrier borrows its target without aliasing its storage.
struct DepBorrowCarrier
{
    public late target: *s32
}

func depBorrowCreateCarrier(target: *s32)->*DepBorrowCarrier
{
    var req: Swag.AllocatorRequest
    req.size = #sizeof(DepBorrowCarrier)
    Swag.getContext().allocator!.alloc(&req)
    let carrier = cast(*DepBorrowCarrier) req.address!
    carrier.target = target
    return carrier
}

func depBorrowCreateCarrierWrapped(target: *s32)->*DepBorrowCarrier
{
    return depBorrowCreateCarrier(target)
}

// The release summary applies to the carrier allocation, never its borrowed target.
func depBorrowReleaseCarrier(carrier: *DepBorrowCarrier)
{
    var req: Swag.AllocatorRequest
    req.address = carrier
    req.size    = #sizeof(DepBorrowCarrier)
    Swag.getContext().allocator!.free(&req)
}

// The spelling in this name must not hide the generated BorrowSummary attribute.
#[Swag.NoInline]
func depBorrowSummaryRead(value: *s32)->s32 => value[]

// Source annotations contribute facts; they cannot erase retention computed from the body.
#[Swag.NoInline, Swag.BorrowSummary(0, observesExternal: false)]
func depBorrowAnnotatedStash(value: *s32)
{
    depBorrowGlobalStash = value
}

var depBorrowObservedOwner: *DepBorrowContainer?

func depBorrowSetObservedOwner(owner: *DepBorrowContainer)
{
    depBorrowObservedOwner = owner
}

#[Swag.NoInline, Swag.BorrowSummary(0, observesExternal: false)]
func depBorrowAnnotatedObserve()
{
    let owner = depBorrowObservedOwner
    if owner do
        depBorrowGlobalStash = owner.slot
}

// An older annotation that omits the external-observation promise stays conservative.
#[Swag.NoInline, Swag.BorrowSummary(0)]
func depBorrowLegacyObserver() {}
