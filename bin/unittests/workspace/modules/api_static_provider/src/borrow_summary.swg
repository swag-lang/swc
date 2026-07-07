#global public

// Borrow summaries must cross the module boundary through the generated API
// ('Swag.BorrowSummary'): consumed by 'consumer_exe'.
var depBorrowGlobalInt: s32 = 7
var depBorrowGlobalStash: *s32

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
func depBorrowStashed()->*s32
{
    return depBorrowGlobalStash
}

// No summary: call sites stay silent whatever was passed.
func depBorrowRead(p: *s32)->s32
{
    return dref p
}

// Pair summary: the item is stored into storage reachable from 'me'.
struct DepBorrowContainer
{
    slot: *s32
}

impl DepBorrowContainer
{
    mtd add(item: *s32)
    {
        .slot = item
    }
}
