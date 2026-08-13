#global private

// Repro for the macro receiver crash: a generic #[Macro] opVisit with an
// explicit `const me` parameter whose body reads an elided member
// (`if !.count`), cloned into a caller whose receiver expression is itself an
// elided member access (`.bag` / `.header.bag`). The macro's `me` binding must
// resolve to the caller expression, not survive as a raw parameter symbol of
// the macro function.
struct(T) Bag
{
    count:  u64
    buffer: #null [*] T
}

impl Bag
{
    mtd set(items: [..] T)
    {
        .buffer = @dataof(items)
        .count  = @countof(items)
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
            let visitIdx = @index

            #static if ptr do
                #inject(stmt, item = cast(*T) scan, index = visitIdx)
            else do
                #inject(stmt, item = scan[0], index = visitIdx)
        }
    }
}

// The padding fields keep every interesting offset non-zero, so resolving the
// elided receiver against the wrong base address reads garbage instead of
// accidentally working.
struct Header
{
    headerPad: u64 = 0xAAAA
    bag:       Bag'u64
}

struct Keeper
{
    keeperPad: u64 = 0xBBBB
    header:    Header
}

impl Keeper
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
            dref v *= k
    }
}

#test
{
    var storage: [3] u64 = [1, 2, 4]
    var kp: Keeper
    kp.header.bag.set(storage)
    @assert(kp.total() == 7)
    @assert(kp.firstAbove(1) == 2)
    kp.scale(10)
    @assert(kp.total() == 70)
}
