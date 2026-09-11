#global private
using Swag

// The products of a loop counter are carried in an accumulator instead of being
// multiplied on every trip. Every function is forced to the optimizing backend
// so the pass runs; the asserted results are the plain unoptimized semantics,
// on the shapes the pass rewrites and on the ones it must leave alone.

var Plane: [16 * 64] u8

func fillPlane()
{
    for i in 16 * 64 do
        Plane[i] = cast(u8) ((i * 7 + 3) & 0xFF)
}

// A register stride and a unit step: the row loop of a pixel kernel.
#[Swag.Optimize(true)]
func sumRows(base: const [*] u8, stride: u64, rows, cols: u64)->u64
{
    var acc: u64
    for row in rows
    {
        let line = base + row * stride
        for col in cols do
            acc += cast(u64) line[col]
    }
    return acc
}

// Three strides on one counter, one of them used twice, sharing accumulators.
#[Swag.Optimize(true)]
func sumThreeStrides(base: const [*] u8, s0, s1, s2: u64, rows: u64)->u64
{
    var acc: u64
    for row in rows
    {
        acc += cast(u64) base[row * s0]
        acc += cast(u64) base[row * s1 + 1]
        acc += cast(u64) base[row * s2 + 2]
        acc += cast(u64) base[row * s0 + 3]
    }
    return acc
}

// An immediate stride and a power-of-two stride, which strength reduction has
// already turned into a shift when the pass sees it.
#[Swag.Optimize(true)]
func sumImmediateStrides(base: const [*] u8, rows: u64)->u64
{
    var acc: u64
    for row in rows
    {
        acc += cast(u64) base[row * 24]
        acc += cast(u64) base[row * 16 + 5]
    }
    return acc
}

// A step of two, and a counter that walks down.
#[Swag.Optimize(true)]
func sumStepTwo(base: const [*] u8, stride: u64, rows: u64)->u64
{
    var acc: u64
    var row: u64
    while row < rows
    {
        acc += cast(u64) base[row * stride]
        row += 2
    }
    return acc
}

#[Swag.Optimize(true)]
func sumDownwards(base: const [*] u8, stride: u64, rows: u64)->u64
{
    var acc: u64
    var row = rows
    while row > 0
    {
        row -= 1
        acc += cast(u64) base[row * stride]
    }
    return acc
}

// A 32-bit counter whose product wraps: the accumulator wraps the same way.
#[Swag.Optimize(true)]
func wrappingProducts(n: u32, stride: u32)->u32
{
    var acc: u32
    for i in n do
        acc = acc + #wrap i * #wrap stride
    return acc
}

// The outer counter's product inside the inner loop, and the counter read after
// the loop.
#[Swag.Optimize(true)]
func nestedProducts(base: const [*] u8, stride: u64, rows, cols: u64)->{ sum: u64, last: u64 }
{
    var acc: u64
    var row: u64
    while row < rows
    {
        for col in cols do
            acc += cast(u64) base[row * stride + col]
        row += 1
    }
    return {acc, row}
}

// A stride the loop changes is not a stride: the multiply stays.
#[Swag.Optimize(true)]
func movingStride(base: const [*] u8, rows: u64)->u64
{
    var acc: u64
    var stride: u64 = 1
    for row in rows
    {
        acc += cast(u64) base[row * stride]
        stride += 1
    }
    return acc
}

// A `continue` skips to the step: the accumulator still follows the counter.
#[Swag.Optimize(true)]
func sumOddRows(base: const [*] u8, stride: u64, rows: u64)->u64
{
    var acc: u64
    for row in rows
    {
        if (row & 1) == 0 do
            continue
        acc += cast(u64) base[row * stride]
    }
    return acc
}

func reference(rows, stride: u64, cols: u64)->u64
{
    var acc: u64
    for row in rows
    {
        for col in cols do
            acc += cast(u64) Plane[row * stride + col]
    }
    return acc
}

#test
{
    fillPlane()
    let base = cast(const [*] u8) &Plane[0]

    Swag.assert(sumRows(base, 64, 16, 40) == reference(16, 64, 40))
    Swag.assert(sumRows(base, 48, 10, 48) == reference(10, 48, 48))
    Swag.assert(sumRows(base, 64, 0, 40) == 0)

    var expected: u64
    for row in 12'u64
    {
        expected += cast(u64) Plane[row * 64]
        expected += cast(u64) Plane[row * 33 + 1]
        expected += cast(u64) Plane[row * 17 + 2]
        expected += cast(u64) Plane[row * 64 + 3]
    }
    Swag.assert(sumThreeStrides(base, 64, 33, 17, 12) == expected)

    expected = 0
    for row in 20'u64
    {
        expected += cast(u64) Plane[row * 24]
        expected += cast(u64) Plane[row * 16 + 5]
    }
    Swag.assert(sumImmediateStrides(base, 20) == expected)

    expected = 0
    var evenRow: u64
    while evenRow < 15
    {
        expected += cast(u64) Plane[evenRow * 64]
        evenRow += 2
    }
    Swag.assert(sumStepTwo(base, 64, 15) == expected)

    expected = 0
    for row in 16'u64 do
        expected += cast(u64) Plane[row * 64]
    Swag.assert(sumDownwards(base, 64, 16) == expected)

    var wrapped: u32
    for i in 1000'u32 do
        wrapped = wrapped + #wrap i * #wrap 0x1000_0001
    Swag.assert(wrappingProducts(1000, 0x1000_0001) == wrapped)

    let nested = nestedProducts(base, 64, 16, 40)
    Swag.assert(nested.sum == reference(16, 64, 40) and nested.last == 16)

    expected = 0
    for row in 30'u64 do
        expected += cast(u64) Plane[row * (row + 1)]
    Swag.assert(movingStride(base, 30) == expected)

    expected = 0
    for row in 16'u64
    {
        if (row & 1) == 1 do
            expected += cast(u64) Plane[row * 64]
    }
    Swag.assert(sumOddRows(base, 64, 16) == expected)
}
