#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-665 - Improper initialization
//
// The value exists but its invariants were never established: a field left unset, an object
// used before its setup ran.
//
// Swag: definite assignment covers the part a flow analysis can see, and it is an ERROR
// rather than a warning. A type with no safe default cannot be observed before every path
// assigns it. A field that is genuinely set later - during setup, not at the declaration -
// says so with 'late', and every read of one is guarded.
// -----------------------------------------------------------------------------

struct Resource
{
    weight: s32
}

var resourceStorage: Resource

// --- Faults ---

// A local of a type with no safe default, observed before it is definitely assigned.
func readBeforeDefiniteAssignment(ready: bool)->s32
{
    var pointer: *Resource
    if ready do
        pointer = &resourceStorage
    return pointer.weight     // swc-expected-error {{sema_err_definite_init_use}}
}

// The same, one field at a time: assigning a sibling does not initialize the aggregate.
struct TwoPointers
{
    first:  *Resource
    second: *Resource
}

func readPartiallyInitialized()->s32
{
    var pair: TwoPointers
    pair.first = &resourceStorage
    return pair.second.weight     // swc-expected-error {{sema_err_definite_init_field_use}}
}

late var lateResource: *Resource

// A 'late' global read before its setup ran: the exposed type is non-null, so the read is
// guarded rather than rejected. The guard is '.Null', not '.Expect' - '!' and 'late' are two
// different assertions and follow two different flags.
#[Swag.Safety(.Null, true)]
func readLateBeforeSetup()->s32
{
    return lateResource.weight     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run readLateBeforeSetup()
}

// --- Sound ---

func assignedOnEveryPath(ready: bool)->s32
{
    var pointer: *Resource
    if ready do
        pointer = &resourceStorage
    else do
        pointer = &resourceStorage
    return pointer.weight
}

// A path that leaves the block reaches none of the code after it, so the other path's
// assignment stands alone.
func assignedAfterEarlyReturn(ready: bool)->s32
{
    var pointer: *Resource
    if !ready do
        return -1
    pointer = &resourceStorage
    return pointer.weight
}

// Comparing the slot with null inspects the sentinel without reading the value.
func lateSlotIsQueryable()->bool
{
    return lateResource != null
}

#test
{
    resourceStorage.weight = 5
    Swag.assert(assignedOnEveryPath(opaqueBool(true)) == 5)
    Swag.assert(assignedAfterEarlyReturn(opaqueBool(false)) == -1)
    Swag.assert(!lateSlotIsQueryable())
    lateResource = &resourceStorage
    Swag.assert(lateSlotIsQueryable())
    Swag.assert(lateResource.weight == 5)
}
