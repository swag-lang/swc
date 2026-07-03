#global private
using Swag

// Loop-invariant code motion regression coverage. Every function is forced to
// the optimizing backend so the LICM pass runs; the asserted results must match
// the obvious unoptimized semantics. The tricky cases (aliasing store/load and
// conditionally executed loads) are here to catch unsound hoisting.

var GTab: [256] s32

#[Swag.Optimize(true)]
func sumInvariantArith(n: s32, k: s32)->s32
{
    var acc = 0
    let base = k * 1000 + 7        // invariant in the loop
    for i in 0 until n do
        acc += base + i
    return acc
}

#[Swag.Optimize(true)]
func sumGlobalLoad(n: s32, idx: s32)->s32
{
    var acc = 0
    for i in 0 until n do
        acc += GTab[idx]           // invariant load (no store in loop): hoistable
    return acc
}

#[Swag.Optimize(true)]
func nestedInvariant(h: s32, w: s32)->s32
{
    var acc = 0
    for y in 0 until h
    {
        let rowv = y * 10          // invariant in the inner loop
        for x in 0 until w do
            acc += rowv + x
    }
    return acc
}

// Aliasing: the loop both writes and reads buf[0], so the load is NOT invariant
// and must not be hoisted. buf[0] = 0,1,2,... after each store.
#[Swag.Optimize(true)]
func aliasStoreLoad(n: s32)->s32
{
    var buf: [4] s32
    buf[0] = 0
    var acc = 0
    for i in 0 until n
    {
        buf[0] = buf[0] + 1
        acc += buf[0]
    }
    return acc
}

// A load that only executes on some iterations must not be speculated out of the
// loop. Here the load of GTab[idx] is guarded by a per-iteration condition.
#[Swag.Optimize(true)]
func guardedLoad(n: s32, idx: s32)->s32
{
    var acc = 0
    for i in 0 until n
    {
        if (i & 1) == 0 do
            acc += GTab[idx]
    }
    return acc
}

struct FieldParams { a, b, c: s64 }

// Frame-aware hoisting: the accumulator is a loop-carried scalar spilled to a
// private frame slot, yet the invariant field loads p.a/p.b/p.c (through a
// pointer that cannot alias the private frame) must be hoisted without changing
// the result.
#[Swag.Optimize(true)]
func reduceFields(n: s32, p: *FieldParams)->s64
{
    var acc: s64 = 0
    for i in 0 until n do
        acc += cast(s64) i * p.a + p.b - p.c
    return acc
}

#test
{
    for i in 0 until 256 do
        GTab[i] = i * 3

    // n*base + n*(n-1)/2 with base = 5*1000+7 = 5007
    @assert(sumInvariantArith(100, 5) == 100 * 5007 + (100 * 99) / 2)
    @assert(sumInvariantArith(1, 5) == 5007)

    // n * GTab[idx]; GTab[10] = 30
    @assert(sumGlobalLoad(50, 10) == 50 * 30)

    // sum over y<h, x<w of (y*10 + x)
    var expectNested = 0
    for y in 0 until 8 do
        for x in 0 until 5 do
            expectNested += y * 10 + x
    @assert(nestedInvariant(8, 5) == expectNested)

    // 1+2+...+n
    @assert(aliasStoreLoad(10) == (10 * 11) / 2)

    // GTab[7]=21, executed on even i (0,2,4): 3 times for n=6
    @assert(guardedLoad(6, 7) == 3 * 21)

    // sum_{i<n} (i*a + b - c) = a*n*(n-1)/2 + (b-c)*n, with a=4,b=100,c=10,n=20
    var fp: FieldParams
    fp.a = 4; fp.b = 100; fp.c = 10
    var expectReduce: s64 = 0
    for i in 0 until 20 do
        expectReduce += cast(s64) i * 4 + 100 - 10
    @assert(reduceFields(20, &fp) == expectReduce)
}
