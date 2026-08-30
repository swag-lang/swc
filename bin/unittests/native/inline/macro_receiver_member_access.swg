#global private

// A #[Macro] visitor with an explicit `const me` receiver, invoked with a
// receiver expression that is itself an elided member access (`.header.bag`).
// The macro body's own elided members (`if !.count`) must resolve against the
// caller's receiver expression: the binding must not leak the leaf field symbol
// (or the macro's raw `me` parameter) into the synthesized member access, since
// neither resolves standalone at codegen. The padding fields keep every
// interesting offset non-zero, so resolving against the wrong base address
// reads garbage instead of accidentally working.
struct(T) VisitBag
{
    count:  u64
    buffer: #null [*] T
}

impl VisitBag
{
    mtd set(items: [..] T)
    {
        .buffer = items.buffer
        .count  = items.count
    }

    #[Swag.Macro]
    func(ptr: bool) opVisit(const me, stmt: #code(item, index: u64))
    {
        if !.count do
            return
        let buffer = .buffer!

        var scan = buffer - 1
        for .count
        {
            scan += 1
            let visitIdx = Swag.index

            #static if ptr do
                #inject(stmt, item = cast(*T) scan, index = visitIdx)
            else do
                #inject(stmt, item = scan[0], index = visitIdx)
        }
    }
}

struct VisitHeader
{
    headerPad: u64 = 0xAAAA
    bag:       VisitBag'u64
}

struct VisitKeeper
{
    keeperPad: u64 = 0xBBBB
    header:    VisitHeader
}

impl VisitKeeper
{
    mtd const total()->u64
    {
        var sum: u64
        for v in .header.bag do
            sum += v
        return sum
    }

    mtd const firstAbove(limit: u64)->u64
    {
        for v in .header.bag where v > limit do
            return v
        return 0
    }

    mtd scale(k: u64)
    {
        for &v in .header.bag do
            v[] *= k
    }
}

#test
{
    var storage: [3] u64 = [1, 2, 4]
    var kp:      VisitKeeper
    kp.header.bag.set(storage)
    Swag.assert(kp.total() == 7)
    Swag.assert(kp.firstAbove(1) == 2)
    kp.scale(10)
    Swag.assert(kp.total() == 70)
}
