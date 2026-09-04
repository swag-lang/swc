#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-825 - Expired pointer dereference
//
// The owner is still alive; the STORAGE the view was reading is not. A container that grows
// moves the very bytes a view addressed, and the view is stale from that moment - which is
// what every language calls iterator invalidation when it happens in a loop.
//
// Swag: proven at compile time, with no annotation. The analysis infers which methods can
// hand what their receiver owns to the allocator ('reallocates'), records the view, and judges
// a later read against the change. It is the rule most people assume needs lifetimes.
//
// The container below is hand-rolled on purpose: the rule must be anchored on the LANGUAGE -
// an owning lifecycle plus a block pointer reaching the allocator - and not on a name in a
// standard module.
// -----------------------------------------------------------------------------

struct Bag
{
    buffer:   [*] s32?
    count:    u64
    capacity: u64
}

impl Bag
{
    mtd opDrop()
    {
        if .buffer != null do
            heapFree(cast(*void) .buffer!, .capacity * 4)
        .buffer = null
    }

    // Reaches the allocator with what the receiver owns, which is what makes this method
    // 'reallocates' and every view taken before it stale.
    mtd grow()
    {
        let capacity = .capacity == 0 ? 4 : .capacity * 2
        let block    = cast([*] s32) heapAlloc(capacity * 4)
        for index in .count do
            block[index] = .buffer![index]
        if .buffer != null do
            heapFree(cast(*void) .buffer!, .capacity * 4)
        .buffer   = block
        .capacity = capacity
    }

    mtd add(value: s32)
    {
        if .count == .capacity do
            .grow()
        .buffer![.count] = value
        .count           += 1
    }

    // Hands out a view INTO the payload, which is what goes stale.
    mtd view()->[..] s32 => Swag.makeSlice(.buffer!, .count)

    mtd const at(index: u64)->s32 => .buffer![index]
}

// --- Faults ---

func readViewAfterGrowth()->s32
{
    var bag: Bag
    bag.add(1)

    let view = bag.view()     // swc-expected-note {{sema_note_borrow_taken_here}}
    bag.add(2)                // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]            // swc-expected-note {{sema_note_borrow_read_here}}
}

// The same rule inside a loop is iterator invalidation.
func mutateWhileIterating()->s32
{
    var bag: Bag
    bag.add(1)
    bag.add(2)

    var total = 0's32
    let view  = bag.view()     // swc-expected-note {{sema_note_borrow_taken_here}}
    for value in view          // swc-expected-note {{sema_note_borrow_read_here}}
    {
        total += value
        bag.add(value)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    }

    return total
}

// --- Sound ---

// A view of the value ITSELF is the handle the change is made through, not a victim of it.
func pointerToTheBagSurvives()->u64
{
    var bag: Bag
    let handle = &bag
    handle.add(1)
    handle.add(2)
    return handle.count
}

// Taking the view again after the change is the fix, and it must stay silent.
func viewRetakenAfterGrowth()->s32
{
    var bag: Bag
    bag.add(1)
    bag.add(2)
    let view = bag.view()
    return view[0]
}

// A 'const' method cannot reach the allocator, so it never invalidates anything.
func constAccessorDoesNotInvalidate()->s32
{
    var bag: Bag
    bag.add(7)
    let view  = bag.view()
    let first = bag.at(0)
    return first + view[0]
}

#test
{
    Swag.assert(pointerToTheBagSurvives() == 2)
    Swag.assert(viewRetakenAfterGrowth() == 1)
    Swag.assert(constAccessorDoesNotInvalidate() == 14)
}
