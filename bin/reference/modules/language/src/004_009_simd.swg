#global private

using Swag

/**
# Simd Vectors

The '#simd' modifier turns a one-dimensional fixed-size array shape into a
packed vector: one 16-byte value whose lanes compute element-wise, in a
single machine register. The shape must total exactly 16 bytes, and the lanes
must be a sized native numeric type: 'u8', 's8', 'u16', 's16', 'u32', 's32',
'u64', 's64', 'f32' or 'f64'.

A vector has value semantics like a scalar: it copies in one move, passes and
returns through one register in the Swag calling convention, and its size and
alignment are both 16 bytes.
*/
#test
{
    var bytes: #simd [16] u8
    var words: #simd [8] s16
    var quads: #simd [4] f32
    Swag.assert(#sizeof(bytes) == 16)
    Swag.assert(#alignof(words) == 16)
    Swag.assert(#sizeof(quads) == 16)
}

/**
# Construction

A vector builds from an array literal with one value per lane, or reinterprets
the matching fixed-size array bit for bit; both fold at compile time when their
operands are constant, and '#bit' reshapes any 16-byte vector or array into
another.

Filling every lane with the same value is a broadcast, not a conversion, so it
has its own operation: 'Swag.vecsplat' takes a scalar and the lane type it carries
names the vector, so a 'u8' fills sixteen lanes and an 'f64' fills two. It folds
like the other forms, which is what lets a vector be declared 'const'.
*/
#test
{
    let lanes: #simd [4] s32 = [1, 2, 3, 4]
    let fours                = Swag.vecsplat(4's32)
    let sum                  = cast([4] s32) (lanes + fours)
    Swag.assert(sum[0] == 5 and sum[3] == 8)

    // A broadcast of a constant is a constant.
    const Ones     = Swag.vecsplat(1'u8)
    const OneLanes = cast([16] u8) Ones
    #assert(OneLanes[0] == 1 and OneLanes[15] == 1)

    var raw: [8] u16 = [1, 2, 3, 4, 5, 6, 7, 8]
    let packed       = cast(#simd [8] u16) raw
    let bytesView    = cast #bit(#simd [16] u8) packed
    let back         = cast([16] u8) bytesView
    Swag.assert(back[0] == 1 and back[2] == 2)
}

/**
# Element-Wise Operators

The arithmetic, bitwise and shift operators compute per lane, and a scalar
operand broadcasts over the other side's lanes. Lane arithmetic always wraps:
a vector is machine data, and no overflow guard applies. The operators follow
what the hardware provides on every target: packed integer divide and modulo
remain unavailable. Integer multiply and shifts without a direct packed
instruction use register-only portable lowerings. Unary '+' is the identity
for every vector shape.
*/
#test
{
    let v = cast(#simd [4] s32) [1, 2, 3, 4]
    let w = cast(#simd [4] s32) [10, 20, 30, 40]

    var r = cast([4] s32) (+v)
    Swag.assert(r[0] == 1 and r[3] == 4)
    r = cast([4] s32) (v + w)
    Swag.assert(r[0] == 11 and r[3] == 44)
    r = cast([4] s32) (w * 2)
    Swag.assert(r[0] == 20 and r[3] == 80)
    r = cast([4] s32) (v << 4)
    Swag.assert(r[0] == 16 and r[3] == 64)

    let bytes        = cast(#simd [16] u8) [0x81, 0x7F, 1, 0, 255, 128, 64, 3, 1, 2, 3, 4, 5, 6, 7, 8]
    let shiftedBytes = cast([16] u8) (bytes << 1)
    Swag.assert(shiftedBytes[0] == 2 and shiftedBytes[1] == 254)

    let wide        = cast(#simd [2] s64) [-8, 0x4000_0000_0000_0000]
    let shiftedWide = cast([2] s64) (wide >> 2)
    Swag.assert(shiftedWide[0] == -2 and shiftedWide[1] == 0x1000_0000_0000_0000)

    let factors1 = cast(#simd [2] u64) [0xFFFF_FFFF_FFFF_FFFF, 0x1_0000_0001]
    let factors2 = cast(#simd [2] u64) [2, 0x1_0000_0001]
    let products = cast([2] u64) (factors1 * factors2)
    Swag.assert(products[0] == 0xFFFF_FFFF_FFFF_FFFE and products[1] == 0x2_0000_0001)

    // Lanes wrap by definition.
    let big  = Swag.vecsplat(2_147_483_647's32)
    let wrap = cast([4] s32) (big + Swag.vecsplat(1's32))
    Swag.assert(wrap[0] == -2_147_483_648)
}

/**
# Comparisons And Masks

An element-wise comparison produces a mask vector, not a bool: unsigned lanes
of the same geometry, all-ones where the compare holds. 'Swag.vecselect' blends
two vectors through a mask, 'Swag.vecmask' gathers the lane sign bits into an
integer, and 'Swag.vecany'/'Swag.vecall' reduce a mask to a bool.
*/
#test
{
    let a = cast(#simd [4] s32) [1, 50, 3, 70]
    let b = cast(#simd [4] s32) [10, 20, 30, 40]

    let mask = a > b
    let m    = cast([4] u32) mask
    Swag.assert(m[0] == 0 and m[1] == 0xFFFF_FFFF)

    let clamped = cast([4] s32) Swag.vecselect(mask, b, a)
    Swag.assert(clamped[0] == 1 and clamped[1] == 20 and clamped[2] == 3 and clamped[3] == 40)

    Swag.assert(Swag.vecmask(mask) == 0b1010)
    Swag.assert(Swag.vecany(mask) and !Swag.vecall(mask))
}

/**
# Lane Access

Lanes read and write like array elements. A constant index is checked at
compile time against the lane count; a dynamic one is bound-checked at run
time like an array index.
*/
#test
{
    var v = cast(#simd [8] s16) [1, 2, 3, 4, 5, 6, 7, 8]
    Swag.assert(v[0] == 1 and v[7] == 8)
    v[3] = 99
    var i: u64 = 3
    Swag.assert(v[i] == 99)
}

/**
# Packed Intrinsics

The 'Swag.vec' intrinsic family carries the operations the operators cannot
express: 'Swag.vecsplat' broadcasts a scalar
into every lane, 'Swag.vecsatadd' and 'Swag.vecsatsub' clamp instead of wrapping,
'Swag.vecpackus' and 'Swag.vecpackss' narrow two vectors with saturation,
'Swag.vecinterleavelo' and 'Swag.vecinterleavehi' alternate lanes from the corresponding
input halves,
'Swag.vecwidenlo' and 'Swag.vecwidenhi' extend half the lanes to double width,
'Swag.vecavgr' is the rounding average, 'Swag.vecmadd' multiplies 16-bit pairs into
32-bit sums and 'Swag.vecmaddubs' does the same for unsigned and signed bytes with
a saturating sum, 'Swag.vecsad' sums the absolute byte differences of each half,
'Swag.vectruncs32' converts four 'f32' lanes to 's32' by truncating
toward zero, 'Swag.vecgather' loads four 's32' values through four 'u32' indices,
and 'Swag.vecperm' permutes bytes through a dynamic table. NaN and
values outside the 's32' range become 's32.Min'. 'Swag.min',
'Swag.max', 'Swag.abs', 'Swag.sqrt', 'Swag.muladd', 'Swag.floor', 'Swag.ceil' and 'Swag.trunc' also accept
vectors and compute per lane. Integer 'Swag.abs' wraps the minimum lane value back
to itself, like unary minus, while a float lane clears its sign bit, so a NaN
stays that NaN and a negative zero becomes a positive one.
A gather uses 'vpgatherdd' when AVX2 is selected
and a portable four-load lowering otherwise; every index must designate a
readable table element and be at most 's32.Max'.
*/
#test
{
    let a = Swag.vecsplat(200'u8)
    let b = Swag.vecsplat(100'u8)
    let r = cast([16] u8) Swag.vecsatadd(a, b)
    Swag.assert(r[0] == 255)

    // The classic codec step: 16-bit intermediates narrowed back to bytes,
    // the clamp riding inside the pack.
    let sums = cast(#simd [8] s16) [-20, 0, 128, 300, 255, 256, 64, 1]
    let px   = cast([16] u8) Swag.vecpackus(sums, sums)
    Swag.assert(px[0] == 0 and px[2] == 128 and px[3] == 255 and px[4] == 255)

    let wide = cast([8] u16) Swag.vecwidenlo(a)
    Swag.assert(wide[0] == 200)

    let indices = cast(#simd [16] u8) [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    let zipped  = cast([16] u8) Swag.vecinterleavelo(indices, b)
    Swag.assert(zipped[0] == 0 and zipped[1] == 100 and zipped[14] == 7 and zipped[15] == 100)

    let avg = cast([16] u8) Swag.vecavgr(a, b)
    Swag.assert(avg[0] == 150)

    let quads = cast(#simd [4] s32) [1, 2, 3, 4]
    Swag.assert(Swag.vecreduceadd(quads) == 10)

    let samples = cast(#simd [4] f32) [1.9, -1.9, 32767.9, -32768.9]
    let ints    = cast([4] s32) Swag.vectruncs32(samples)
    Swag.assert(ints[0] == 1 and ints[1] == -1 and ints[2] == 32767 and ints[3] == -32768)

    var lookup: [5] s32 = [10, 20, 30, 40, 50]
    let found           = cast([4] s32) Swag.vecgather(lookup.buffer, cast(#simd [4] u32) [4, 0, 3, 1])
    Swag.assert(found[0] == 50 and found[1] == 10 and found[2] == 40 and found[3] == 20)
}

/**
# The Other Half Of A Product

'*' answers the low half of a lane product, the bits that fit the lane.
'Swag.vecmulhi' answers the ones above it, read as the lane type is signed or not.
Together they are the whole product: interleaving them puts each double-width
product back in the lane it belongs to, which is what
'Core.Math.Simd.mulWidenLow' and 'mulWidenHigh' do.

A 16-bit lane has the instruction directly. The other widths compose it: bytes
widen to words where the product is exact, 32-bit lanes take the two widening
products the hardware offers and gather their high halves, and 64-bit lanes add
up the four partial products of their halves.
*/
#test
{
    let x = cast(#simd [8] s16) [-32768, 32767, 1000, -1000, 3, -3, 0, 12345]
    let y = cast(#simd [8] s16) [32767, 32767, -2000, 2000, 5, 5, 12345, -1]

    let low  = cast([8] s16) (x * y)
    let high = cast([8] s16) Swag.vecmulhi(x, y)

    // 1000 * -2000 is -2000000, which is 0xFFE17B80 over two lanes.
    Swag.assert(cast #bit (u16) low[2] == 0x7B80 and cast #bit (u16) high[2] == 0xFFE1)

    // Read as unsigned, the same bits give a different half above the lane.
    let unsignedHigh = cast([8] u16) Swag.vecmulhi(cast #bit (#simd [8] u16) x, cast #bit (#simd [8] u16) y)
    Swag.assert(unsignedHigh[2] == 0x03C9)
}

/**
# Lane Permutation

'Swag.vecshuffle' rearranges the lanes of a vector: result lane 'i' takes the lane
its pattern lane names, the index reduced modulo the lane count so no pattern
is out of range. 'Swag.vecshuffle2' does the same over two vectors, an index below
the lane count reading the first and one above it reading the second at the
index minus that count. 'Swag.vecalign' takes sixteen bytes of the concatenation of
two vectors starting at a byte offset, and answers zero past the thirty-two.

A pattern the compiler can see selects an immediate form where the target has
one: a permutation of 32-bit lanes is one 'pshufd', a two-source pattern whose
low half comes from one vector and whose high half comes from the other is one
'shufps', and a constant byte offset is one 'palignr'. Everything else becomes
a permute against a constant byte table. A pattern that only exists at run time
keeps the same meaning through the dynamic byte permute, which is what
'Swag.vecperm' exposes on its own.
*/
#test
{
    let quads = cast(#simd [4] u32) [10, 20, 30, 40]

    var r = cast([4] u32) Swag.vecshuffle(quads, cast(#simd [4] u32) [3, 2, 1, 0])
    Swag.assert(r[0] == 40 and r[1] == 30 and r[2] == 20 and r[3] == 10)

    // An index past the last lane wraps around instead of reading nothing.
    r = cast([4] u32) Swag.vecshuffle(quads, cast(#simd [4] u32) [4, 5, 6, 7])
    Swag.assert(r[0] == 10 and r[3] == 40)

    let other = cast(#simd [4] u32) [50, 60, 70, 80]
    r = cast([4] u32) Swag.vecshuffle2(quads, other, cast(#simd [4] u32) [0, 2, 5, 7])
    Swag.assert(r[0] == 10 and r[1] == 30 and r[2] == 60 and r[3] == 80)

    let bytes = cast(#simd [16] u8) [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    let next  = cast(#simd [16] u8) [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
    let slid  = cast([16] u8) Swag.vecalign(bytes, next, 4)
    Swag.assert(slid[0] == 4 and slid[11] == 15 and slid[12] == 16 and slid[15] == 19)

    // Past the concatenation there is nothing to read.
    let empty = cast([16] u8) Swag.vecalign(bytes, next, 32)
    Swag.assert(empty[0] == 0 and empty[15] == 0)
}

/**
# Horizontal Reductions

The 'Swag.vecreduce' family combines every lane of a vector into one scalar of the
lane type: 'Swag.vecreduceadd' sums, 'Swag.vecreducemin' and 'Swag.vecreducemax' select,
and 'Swag.vecreduceand', 'Swag.vecreduceor' and 'Swag.vecreducexor' fold the bits of
integer lanes.

Adjacent lanes combine first and their results after, so the order is a
balanced tree over the lane index; that order is what a float sum observes.
Integer sums wrap like every other lane arithmetic. The float minimum and
maximum follow the element-wise 'Swag.min' and 'Swag.max', which answer their second
operand when either side is a NaN, so a NaN does not propagate out of a
reduction.

Nothing here goes through memory: each step slides the upper half of the
vector down and applies one element-wise operation.
*/
#test
{
    let quads = cast(#simd [4] s32) [1, 2, 3, 4]
    Swag.assert(Swag.vecreduceadd(quads) == 10)
    Swag.assert(Swag.vecreducemin(quads) == 1)
    Swag.assert(Swag.vecreducemax(quads) == 4)

    let bits = cast(#simd [4] u32) [0b1110, 0b1010, 0b1111, 0b0110]
    Swag.assert(Swag.vecreduceand(bits) == 0b0010)
    Swag.assert(Swag.vecreduceor(bits) == 0b1111)
    Swag.assert(Swag.vecreducexor(bits) == 0b1101)

    // An integer sum wraps, like every other lane arithmetic.
    let edge = cast(#simd [4] s32) [2_147_483_647, 1, 0, 0]
    Swag.assert(Swag.vecreduceadd(edge) == -2_147_483_648)

    let floats = cast(#simd [4] f32) [1.5, -2.5, 8.0, 0.25]
    Swag.assert(Swag.vecreduceadd(floats) == 7.25)
    Swag.assert(Swag.vecreducemin(floats) == -2.5)
    Swag.assert(Swag.vecreducemax(floats) == 8.0)

    // The absolute byte differences of each half land in one 64-bit lane each.
    let left  = cast(#simd [16] u8) [10, 20, 30, 40, 50, 60, 70, 80, 0, 0, 0, 0, 0, 0, 0, 0]
    let right = cast(#simd [16] u8) [1, 2, 3, 4, 5, 6, 7, 8, 255, 0, 0, 0, 0, 0, 0, 0]
    let diffs = cast([2] u64) Swag.vecsad(left, right)
    Swag.assert(diffs[0] == 9 + 18 + 27 + 36 + 45 + 54 + 63 + 72 and diffs[1] == 255)
}

/**
# Packed Bit Operations

The bit intrinsics accept vectors of unsigned lanes and answer, for every lane,
what the scalar form answers for one value of that width. 'Swag.rol' and 'Swag.ror'
rotate by a count taken modulo the lane width, so a count of zero or of one
whole width is the identity. 'Swag.bitCountNz' counts the bits set, 'Swag.bitCountTz'
and 'Swag.bitCountLz' count the zeros below the lowest and above the highest set
bit, and an all-zero lane answers the lane width. 'Swag.byteSwap' reverses the
bytes inside every lane.

None of these has a single packed instruction on the baseline target: a
constant rotation is a shift pair, a variable one reduces its count first, the
counts go through a nibble table, and the byte reversal is one dynamic permute.
*/
#test
{
    let quads = cast(#simd [4] u32) [0, 1, 0x1234_5678, 0xFFFF_FFFF]

    let rotated = cast([4] u32) Swag.rol(quads, 8)
    Swag.assert(rotated[1] == 0x100 and rotated[2] == 0x3456_7812)
    let restored = cast([4] u32) Swag.ror(Swag.rol(quads, 8), 8)
    Swag.assert(restored[2] == 0x1234_5678)

    // The count reduces modulo the lane width, so a whole turn changes nothing.
    let turned = cast([4] u32) Swag.rol(quads, 32)
    Swag.assert(turned[2] == 0x1234_5678)

    let ones = cast([4] u32) Swag.bitCountNz(quads)
    Swag.assert(ones[0] == 0 and ones[1] == 1 and ones[3] == 32)

    // An empty lane answers the lane width for both counts.
    let below = cast([4] u32) Swag.bitCountTz(quads)
    let above = cast([4] u32) Swag.bitCountLz(quads)
    Swag.assert(below[0] == 32 and below[1] == 0 and below[2] == 3)
    Swag.assert(above[0] == 32 and above[1] == 31 and above[3] == 0)

    let swapped = cast([4] u32) Swag.byteSwap(quads)
    Swag.assert(swapped[1] == 0x0100_0000 and swapped[2] == 0x7856_3412)

    let magnitude = cast([4] f32) Swag.abs(cast(#simd [4] f32) [-1.5, 2.5, -0.0, -8.25])
    Swag.assert(magnitude[0] == 1.5 and magnitude[3] == 8.25)
}

/**
# Boundaries

A vector crosses module boundaries in the Swag calling convention only: a
'#[Swag.Foreign]' declaration with a C calling convention does not accept a
simd parameter or return type. Inside Swag code a vector behaves like any
value: struct fields, arrays of vectors, and compile-time execution all work.
*/
#test
{
    struct Pixels
    {
        row: #simd [16] u8
    }

    var p: Pixels
    p.row = Swag.vecsplat(7'u8)
    Swag.assert(p.row[15] == 7)
}
