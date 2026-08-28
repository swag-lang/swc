#global private

// Macro receivers whose expression contains an INDEX through a user struct
// (opIndexPtr lowering): the per-elided-use clone of the receiver expression
// must re-lower the index when re-analyzed inside the macro expansion.
// Mirrors tagbin.swg `for &sf in .shapes[shapeId].fields`.
struct(T) Rack
{
    count:  u64
    buffer: #null [*] T
}

impl Rack
{
    mtd set(items: [..] T)
    {
        .buffer = @dataof(items)
        .count  = @countof(items)
    }

    mtd const opIndexPtr(index: u64)->const *T
    {
        let buffer = .buffer!
        return buffer + index
    }

    mtd opIndexPtr(index: u64)->*T
    {
        let buffer = .buffer!
        return buffer + index
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

struct Crate
{
    cratePad: u64 = 0xCCCC
    inner:    Rack'u64
}

struct Depot
{
    depotPad: u64 = 0xDDDD
    racks:    Rack'(Rack'u64)
    crates:   Rack'Crate
}

impl Depot
{
    // Receiver with a trailing index: `.racks[i]` is itself the visited value. Keep the method
    // inline in every build configuration so the macro expands below an ordinary inline payload.
    #[Swag.Inline]
    mtd const sumRack(i: u64)->u64
    {
        var sum: u64
        for v in .racks[i] do
            sum += v
        return sum
    }

    // Receiver with an index in the middle of the chain, like tagbin's
    // `.shapes[shapeId].fields`.
    mtd const sumCrate(i: u64)->u64
    {
        var sum: u64
        for v in .crates[i].inner do
            sum += v
        return sum
    }

    mtd scaleCrate(i, k: u64)
    {
        for &v in .crates[i].inner do
            v[] *= k
    }
}

#test
{
    var values: [3] u64 = [1, 2, 4]
    var more:   [2] u64 = [10, 20]

    var rackA: Rack'u64
    rackA.set(values)
    var rackB: Rack'u64
    rackB.set(more)
    var pair: [2] Rack'u64 = [rackA, rackB]

    var crateA: Crate
    crateA.inner.set(values)
    var crateB: Crate
    crateB.inner.set(more)
    var crates: [2] Crate = [crateA, crateB]

    var depot: Depot
    depot.racks.set(pair)
    depot.crates.set(crates)

    @assert(depot.sumRack(0) == 7)
    @assert(depot.sumRack(1) == 30)
    @assert(depot.sumCrate(0) == 7)
    @assert(depot.sumCrate(1) == 30)
    depot.scaleCrate(0, 10)
    @assert(depot.sumCrate(0) == 70)
}
