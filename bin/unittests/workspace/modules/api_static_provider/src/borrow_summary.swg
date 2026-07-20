#global public

// Borrow summaries must cross the module boundary through the generated API
// ('Swag.BorrowSummary'): consumed by 'consumer_exe'.
var depBorrowGlobalInt: s32 = 7
var depBorrowGlobalStash: #null *s32

// Return summary: the result borrows the parameter.
func depBorrowPassthrough(p: #nonull *s32)->#nonull *s32
{
    return p
}

// Transitive return summary through a wrapper.
func depBorrowWrap(p: #nonull *s32)->#nonull *s32
{
    return depBorrowPassthrough(p)
}

// Stores summary: the parameter is kept beyond the call.
func depBorrowStash(p: #nonull *s32)
{
    depBorrowGlobalStash = p
}

// Globals are not exported in the generated API: read the stash through a function.
func depBorrowStashed()->#null *s32
{
    return depBorrowGlobalStash
}

// No summary: call sites stay silent whatever was passed.
func depBorrowRead(p: #nonull *s32)->s32
{
    return dref p
}

// Every parameter carried by an aggregate contributes to the exported return summary.
struct DepBorrowPair
{
    first:  #nonull *s32
    second: #nonull *s32
}

func depBorrowMakePair(first, second: #nonull *s32)->DepBorrowPair
{
    return {first, second}
}

// Pair summary: the item is stored into storage reachable from 'me'.
struct DepBorrowContainer
{
    slot: #null *s32
}

impl DepBorrowContainer
{
    mtd add(item: #nonull *s32)
    {
        .slot = item
    }
}
