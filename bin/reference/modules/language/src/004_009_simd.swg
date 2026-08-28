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
    @assert(#sizeof(bytes) == 16)
    @assert(#alignof(words) == 16)
    @assert(#sizeof(quads) == 16)
}

/**
# Construction

A vector builds from an array literal with one value per lane, or reinterprets
the matching fixed-size array bit for bit; both fold at compile time when their
operands are constant, and '#bit' reshapes any 16-byte vector or array into
another.

Filling every lane with the same value is a broadcast, not a conversion, so it
has its own operation: '@vecsplat' takes a scalar and the lane type it carries
names the vector, so a 'u8' fills sixteen lanes and an 'f64' fills two. It folds
like the other forms, which is what lets a vector be declared 'const'.
*/
#test
{
    let lanes: #simd [4] s32 = [1, 2, 3, 4]
    let fours                = @vecsplat(4's32)
    let sum                  = cast([4] s32) (lanes + fours)
    @assert(sum[0] == 5 and sum[3] == 8)

    // A broadcast of a constant is a constant.
    const Ones     = @vecsplat(1'u8)
    const OneLanes = cast([16] u8) Ones
    #assert(OneLanes[0] == 1 and OneLanes[15] == 1)

    var raw: [8] u16 = [1, 2, 3, 4, 5, 6, 7, 8]
    let packed       = cast(#simd [8] u16) raw
    let bytesView    = cast #bit(#simd [16] u8) packed
    let back         = cast([16] u8) bytesView
    @assert(back[0] == 1 and back[2] == 2)
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
    @assert(r[0] == 1 and r[3] == 4)
    r = cast([4] s32) (v + w)
    @assert(r[0] == 11 and r[3] == 44)
    r = cast([4] s32) (w * 2)
    @assert(r[0] == 20 and r[3] == 80)
    r = cast([4] s32) (v << 4)
    @assert(r[0] == 16 and r[3] == 64)

    let bytes        = cast(#simd [16] u8) [0x81, 0x7F, 1, 0, 255, 128, 64, 3, 1, 2, 3, 4, 5, 6, 7, 8]
    let shiftedBytes = cast([16] u8) (bytes << 1)
    @assert(shiftedBytes[0] == 2 and shiftedBytes[1] == 254)

    let wide        = cast(#simd [2] s64) [-8, 0x4000_0000_0000_0000]
    let shiftedWide = cast([2] s64) (wide >> 2)
    @assert(shiftedWide[0] == -2 and shiftedWide[1] == 0x1000_0000_0000_0000)

    let factors1 = cast(#simd [2] u64) [0xFFFF_FFFF_FFFF_FFFF, 0x1_0000_0001]
    let factors2 = cast(#simd [2] u64) [2, 0x1_0000_0001]
    let products = cast([2] u64) (factors1 * factors2)
    @assert(products[0] == 0xFFFF_FFFF_FFFF_FFFE and products[1] == 0x2_0000_0001)

    // Lanes wrap by definition.
    let big  = @vecsplat(2_147_483_647's32)
    let wrap = cast([4] s32) (big + @vecsplat(1's32))
    @assert(wrap[0] == -2_147_483_648)
}

/**
# Comparisons And Masks

An element-wise comparison produces a mask vector, not a bool: unsigned lanes
of the same geometry, all-ones where the compare holds. '@vecselect' blends
two vectors through a mask, '@vecmask' gathers the lane sign bits into an
integer, and '@vecany'/'@vecall' reduce a mask to a bool.
*/
#test
{
    let a = cast(#simd [4] s32) [1, 50, 3, 70]
    let b = cast(#simd [4] s32) [10, 20, 30, 40]

    let mask = a > b
    let m    = cast([4] u32) mask
    @assert(m[0] == 0 and m[1] == 0xFFFF_FFFF)

    let clamped = cast([4] s32) @vecselect(mask, b, a)
    @assert(clamped[0] == 1 and clamped[1] == 20 and clamped[2] == 3 and clamped[3] == 40)

    @assert(@vecmask(mask) == 0b1010)
    @assert(@vecany(mask) and !@vecall(mask))
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
    @assert(v[0] == 1 and v[7] == 8)
    v[3] = 99
    var i: u64 = 3
    @assert(v[i] == 99)
}

/**
# Packed Intrinsics

The '@vec' intrinsic family carries the operations the operators cannot
express: '@vecsplat' broadcasts a scalar
into every lane, '@vecsatadd' and '@vecsatsub' clamp instead of wrapping,
'@vecpackus' and '@vecpackss' narrow two vectors with saturation,
'@vecinterleavelo' and '@vecinterleavehi' alternate lanes from the corresponding
input halves,
'@vecwidenlo' and '@vecwidenhi' extend half the lanes to double width,
'@vecavgr' is the rounding average, '@vecmadd' multiplies 16-bit pairs into
32-bit sums and '@vecmaddubs' does the same for unsigned and signed bytes with
a saturating sum, '@vecsad' sums the absolute byte differences of each half,
'@vectruncs32' converts four 'f32' lanes to 's32' by truncating
toward zero, '@vecgather' loads four 's32' values through four 'u32' indices,
and '@vecperm' permutes bytes through a dynamic table. NaN and
values outside the 's32' range become 's32.Min'. '@min',
'@max', '@abs', '@sqrt', '@muladd', '@floor', '@ceil' and '@trunc' also accept
vectors and compute per lane. Integer '@abs' wraps the minimum lane value back
to itself, like unary minus, while a float lane clears its sign bit, so a NaN
stays that NaN and a negative zero becomes a positive one.
A gather uses 'vpgatherdd' when AVX2 is selected
and a portable four-load lowering otherwise; every index must designate a
readable table element and be at most 's32.Max'.
*/
#test
{
    let a = @vecsplat(200'u8)
    let b = @vecsplat(100'u8)
    let r = cast([16] u8) @vecsatadd(a, b)
    @assert(r[0] == 255)

    // The classic codec step: 16-bit intermediates narrowed back to bytes,
    // the clamp riding inside the pack.
    let sums = cast(#simd [8] s16) [-20, 0, 128, 300, 255, 256, 64, 1]
    let px   = cast([16] u8) @vecpackus(sums, sums)
    @assert(px[0] == 0 and px[2] == 128 and px[3] == 255 and px[4] == 255)

    let wide = cast([8] u16) @vecwidenlo(a)
    @assert(wide[0] == 200)

    let indices = cast(#simd [16] u8) [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    let zipped  = cast([16] u8) @vecinterleavelo(indices, b)
    @assert(zipped[0] == 0 and zipped[1] == 100 and zipped[14] == 7 and zipped[15] == 100)

    let avg = cast([16] u8) @vecavgr(a, b)
    @assert(avg[0] == 150)

    let quads = cast(#simd [4] s32) [1, 2, 3, 4]
    @assert(@vecreduceadd(quads) == 10)

    let samples = cast(#simd [4] f32) [1.9, -1.9, 32767.9, -32768.9]
    let ints    = cast([4] s32) @vectruncs32(samples)
    @assert(ints[0] == 1 and ints[1] == -1 and ints[2] == 32767 and ints[3] == -32768)

    var lookup: [5] s32 = [10, 20, 30, 40, 50]
    let found           = cast([4] s32) @vecgather(@dataof(lookup), cast(#simd [4] u32) [4, 0, 3, 1])
    @assert(found[0] == 50 and found[1] == 10 and found[2] == 40 and found[3] == 20)
}

/**
# Lane Permutation

'@vecshuffle' rearranges the lanes of a vector: result lane 'i' takes the lane
its pattern lane names, the index reduced modulo the lane count so no pattern
is out of range. '@vecshuffle2' does the same over two vectors, an index below
the lane count reading the first and one above it reading the second at the
index minus that count. '@vecalign' takes sixteen bytes of the concatenation of
two vectors starting at a byte offset, and answers zero past the thirty-two.

A pattern the compiler can see selects an immediate form where the target has
one: a permutation of 32-bit lanes is one 'pshufd', a two-source pattern whose
low half comes from one vector and whose high half comes from the other is one
'shufps', and a constant byte offset is one 'palignr'. Everything else becomes
a permute against a constant byte table. A pattern that only exists at run time
keeps the same meaning through the dynamic byte permute, which is what
'@vecperm' exposes on its own.
*/
#test
{
    let quads = cast(#simd [4] u32) [10, 20, 30, 40]

    var r = cast([4] u32) @vecshuffle(quads, cast(#simd [4] u32) [3, 2, 1, 0])
    @assert(r[0] == 40 and r[1] == 30 and r[2] == 20 and r[3] == 10)

    // An index past the last lane wraps around instead of reading nothing.
    r = cast([4] u32) @vecshuffle(quads, cast(#simd [4] u32) [4, 5, 6, 7])
    @assert(r[0] == 10 and r[3] == 40)

    let other = cast(#simd [4] u32) [50, 60, 70, 80]
    r = cast([4] u32) @vecshuffle2(quads, other, cast(#simd [4] u32) [0, 2, 5, 7])
    @assert(r[0] == 10 and r[1] == 30 and r[2] == 60 and r[3] == 80)

    let bytes = cast(#simd [16] u8) [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    let next  = cast(#simd [16] u8) [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
    let slid  = cast([16] u8) @vecalign(bytes, next, 4)
    @assert(slid[0] == 4 and slid[11] == 15 and slid[12] == 16 and slid[15] == 19)

    // Past the concatenation there is nothing to read.
    let empty = cast([16] u8) @vecalign(bytes, next, 32)
    @assert(empty[0] == 0 and empty[15] == 0)
}

/**
# Horizontal Reductions

The '@vecreduce' family combines every lane of a vector into one scalar of the
lane type: '@vecreduceadd' sums, '@vecreducemin' and '@vecreducemax' select,
and '@vecreduceand', '@vecreduceor' and '@vecreducexor' fold the bits of
integer lanes.

Adjacent lanes combine first and their results after, so the order is a
balanced tree over the lane index; that order is what a float sum observes.
Integer sums wrap like every other lane arithmetic. The float minimum and
maximum follow the element-wise '@min' and '@max', which answer their second
operand when either side is a NaN, so a NaN does not propagate out of a
reduction.

Nothing here goes through memory: each step slides the upper half of the
vector down and applies one element-wise operation.
*/
#test
{
    let quads = cast(#simd [4] s32) [1, 2, 3, 4]
    @assert(@vecreduceadd(quads) == 10)
    @assert(@vecreducemin(quads) == 1)
    @assert(@vecreducemax(quads) == 4)

    let bits = cast(#simd [4] u32) [0b1110, 0b1010, 0b1111, 0b0110]
    @assert(@vecreduceand(bits) == 0b0010)
    @assert(@vecreduceor(bits) == 0b1111)
    @assert(@vecreducexor(bits) == 0b1101)

    // An integer sum wraps, like every other lane arithmetic.
    let edge = cast(#simd [4] s32) [2_147_483_647, 1, 0, 0]
    @assert(@vecreduceadd(edge) == -2_147_483_648)

    let floats = cast(#simd [4] f32) [1.5, -2.5, 8.0, 0.25]
    @assert(@vecreduceadd(floats) == 7.25)
    @assert(@vecreducemin(floats) == -2.5)
    @assert(@vecreducemax(floats) == 8.0)

    // The absolute byte differences of each half land in one 64-bit lane each.
    let left  = cast(#simd [16] u8) [10, 20, 30, 40, 50, 60, 70, 80, 0, 0, 0, 0, 0, 0, 0, 0]
    let right = cast(#simd [16] u8) [1, 2, 3, 4, 5, 6, 7, 8, 255, 0, 0, 0, 0, 0, 0, 0]
    let diffs = cast([2] u64) @vecsad(left, right)
    @assert(diffs[0] == 9 + 18 + 27 + 36 + 45 + 54 + 63 + 72 and diffs[1] == 255)
}

/**
# Packed Bit Operations

The bit intrinsics accept vectors of unsigned lanes and answer, for every lane,
what the scalar form answers for one value of that width. '@rol' and '@ror'
rotate by a count taken modulo the lane width, so a count of zero or of one
whole width is the identity. '@bitcountnz' counts the bits set, '@bitcounttz'
and '@bitcountlz' count the zeros below the lowest and above the highest set
bit, and an all-zero lane answers the lane width. '@byteswap' reverses the
bytes inside every lane.

None of these has a single packed instruction on the baseline target: a
constant rotation is a shift pair, a variable one reduces its count first, the
counts go through a nibble table, and the byte reversal is one dynamic permute.
*/
#test
{
    let quads = cast(#simd [4] u32) [0, 1, 0x1234_5678, 0xFFFF_FFFF]

    let rotated = cast([4] u32) @rol(quads, 8)
    @assert(rotated[1] == 0x100 and rotated[2] == 0x3456_7812)
    let restored = cast([4] u32) @ror(@rol(quads, 8), 8)
    @assert(restored[2] == 0x1234_5678)

    // The count reduces modulo the lane width, so a whole turn changes nothing.
    let turned = cast([4] u32) @rol(quads, 32)
    @assert(turned[2] == 0x1234_5678)

    let ones = cast([4] u32) @bitcountnz(quads)
    @assert(ones[0] == 0 and ones[1] == 1 and ones[3] == 32)

    // An empty lane answers the lane width for both counts.
    let below = cast([4] u32) @bitcounttz(quads)
    let above = cast([4] u32) @bitcountlz(quads)
    @assert(below[0] == 32 and below[1] == 0 and below[2] == 3)
    @assert(above[0] == 32 and above[1] == 31 and above[3] == 0)

    let swapped = cast([4] u32) @byteswap(quads)
    @assert(swapped[1] == 0x0100_0000 and swapped[2] == 0x7856_3412)

    let magnitude = cast([4] f32) @abs(cast(#simd [4] f32) [-1.5, 2.5, -0.0, -8.25])
    @assert(magnitude[0] == 1.5 and magnitude[3] == 8.25)
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
    p.row = @vecsplat(7'u8)
    @assert(p.row[15] == 7)
}
