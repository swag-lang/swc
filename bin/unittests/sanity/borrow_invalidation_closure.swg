#global private
// Borrow invalidation inside a function expression and inside a closure: a body nested
// in another function is judged on its own views, whatever its capture list.
#global #[Swag.Sanity(.Lifecycle, true)]
using Swag

struct BorrowInvClosureBuffer
{
    data:     [*] u8?
    length:   u64
    capacity: u64
}

impl BorrowInvClosureBuffer
{
    mtd opDrop()
    {
        if not .data do
            return

        var req: AllocatorRequest
        req.address = .data
        req.size    = .capacity

        let alloc = Swag.getContext().allocator!
        alloc.free(&req)
    }

    // Grows the payload: the block can move.
    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return

        var req: AllocatorRequest
        req.address = .data
        req.size    = newCapacity
        req.oldSize = .capacity

        let alloc = Swag.getContext().allocator!
        alloc.realloc(&req)

        .data     = cast(req.address)
        .capacity = newCapacity
    }
}

alias BorrowInvClosureFn = func||()->u8

func borrowInvInFunctionExpr()->u8
{
    let fn = func()->u8
    {
        var buf: BorrowInvClosureBuffer
        buf.reserve(4)
        let view = buf.data!
        buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
        return view[0]
    }

    return fn()
}

func borrowInvInClosure()->u8
{
    let seed: u64 = 4
    let cb:   BorrowInvClosureFn = func|seed|()->u8
    {
        var buf: BorrowInvClosureBuffer
        buf.reserve(seed)
        let view = buf.data!
        buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
        return view[0]
    }

    return cb()
}
