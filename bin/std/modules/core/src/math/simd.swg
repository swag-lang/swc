#global export
#global namespace Math
#global public

using Swag

// Packed 128-bit vector operations over the '#simd [N] T' types.
//
// The aliases name every legal 16-byte vector shape, lane type by lane count, and the
// functions give the packed hardware intrinsics their product spelling: memory transfers,
// saturating arithmetic, narrowing and widening, byte shuffles, and mask handling. Every
// operation maps directly to packed backend operations. A gather can use several indexed
// loads when the baseline instruction set has no native gather instruction.
//
// The rest of the vector vocabulary needs no function at all. Comparisons and the
// arithmetic, bitwise and shift operators are part of the language and compute per lane,
// and a scalar operand of an operator broadcasts over the other side's lanes. A `cast`
// reshapes 16 bytes — an array of the exact shape into a vector and back — while
// `cast #bit` reinterprets one vector shape as another. The element-wise forms of
// [[Math.min]], [[Math.max]], [[Math.abs]], [[Math.sqrt]], [[Math.mulAdd]], [[Math.floor]],
// [[Math.ceil]] and [[Math.trunc]] accept the vector types directly, and so do the bit
// operations [[Math.rol]], [[Math.ror]], [[Math.countOnes]], [[Math.leadingZeros]],
// [[Math.trailingZeros]], [[Math.byteswap]] and [[Math.reverse]].
namespace Simd
{
    alias U8x16 = #simd [16] u8     // Sixteen unsigned 8-bit lanes.
    alias S8x16 = #simd [16] s8     // Sixteen signed 8-bit lanes.
    alias U16x8 = #simd [8] u16     // Eight unsigned 16-bit lanes.
    alias S16x8 = #simd [8] s16     // Eight signed 16-bit lanes.
    alias U32x4 = #simd [4] u32     // Four unsigned 32-bit lanes.
    alias S32x4 = #simd [4] s32     // Four signed 32-bit lanes.
    alias U64x2 = #simd [2] u64     // Two unsigned 64-bit lanes.
    alias S64x2 = #simd [2] s64     // Two signed 64-bit lanes.
    alias F32x4 = #simd [4] f32     // Four 32-bit float lanes.
    alias F64x2 = #simd [2] f64     // Two 64-bit float lanes.

    #[Inline]
    {
        // Fills every lane with one scalar.
        //
        // The lane type names the vector, so a `u8` fills sixteen lanes and an `f64` fills
        // two. A vector is never built by conversion: `cast` reshapes 16 bytes, and this
        // copies one value across them.
        func splat(value: u8)->U8x16  => @vecsplat(value)
        func splat(value: s8)->S8x16  => @vecsplat(value)
        func splat(value: u16)->U16x8 => @vecsplat(value)
        func splat(value: s16)->S16x8 => @vecsplat(value)
        func splat(value: u32)->U32x4 => @vecsplat(value)
        func splat(value: s32)->S32x4 => @vecsplat(value)
        func splat(value: u64)->U64x2 => @vecsplat(value)
        func splat(value: s64)->S64x2 => @vecsplat(value)
        func splat(value: f32)->F32x4 => @vecsplat(value)
        func splat(value: f64)->F64x2 => @vecsplat(value)

        // Reads one vector from memory; the pointer needs no particular alignment.
        //
        // The lane type of the pointer selects the vector shape, so a byte pointer
        // reads a [[Simd.U8x16]], a `s16` pointer a [[Simd.S16x8]], and so on.
        func load(source: const [*] u8)->U8x16  => (cast(const [*] U8x16) source)[0]
        func load(source: const [*] s8)->S8x16  => (cast(const [*] S8x16) source)[0]
        func load(source: const [*] u16)->U16x8 => (cast(const [*] U16x8) source)[0]
        func load(source: const [*] s16)->S16x8 => (cast(const [*] S16x8) source)[0]
        func load(source: const [*] u32)->U32x4 => (cast(const [*] U32x4) source)[0]
        func load(source: const [*] s32)->S32x4 => (cast(const [*] S32x4) source)[0]
        func load(source: const [*] u64)->U64x2 => (cast(const [*] U64x2) source)[0]
        func load(source: const [*] s64)->S64x2 => (cast(const [*] S64x2) source)[0]
        func load(source: const [*] f32)->F32x4 => (cast(const [*] F32x4) source)[0]
        func load(source: const [*] f64)->F64x2 => (cast(const [*] F64x2) source)[0]

        // Writes one vector to memory; the pointer needs no particular alignment.
        func store(destination: [*] u8, value: U8x16) { (cast([*] U8x16) destination)[0] = value; }
        func store(destination: [*] s8, value: S8x16) { (cast([*] S8x16) destination)[0] = value; }
        func store(destination: [*] u16, value: U16x8) { (cast([*] U16x8) destination)[0] = value; }
        func store(destination: [*] s16, value: S16x8) { (cast([*] S16x8) destination)[0] = value; }
        func store(destination: [*] u32, value: U32x4) { (cast([*] U32x4) destination)[0] = value; }
        func store(destination: [*] s32, value: S32x4) { (cast([*] S32x4) destination)[0] = value; }
        func store(destination: [*] u64, value: U64x2) { (cast([*] U64x2) destination)[0] = value; }
        func store(destination: [*] s64, value: S64x2) { (cast([*] S64x2) destination)[0] = value; }
        func store(destination: [*] f32, value: F32x4) { (cast([*] F32x4) destination)[0] = value; }
        func store(destination: [*] f64, value: F64x2) { (cast([*] F64x2) destination)[0] = value; }

        // Writes the low eight bytes of a byte vector to memory, as one 64-bit move.
        func storeLow8(destination: [*] u8, value: U8x16) { (cast([*] u64) destination)[0] = (cast #bit(U64x2) value)[0]; }

        // Writes the low four bytes of a byte vector to memory, as one 32-bit move.
        func storeLow4(destination: [*] u8, value: U8x16) { (cast([*] u32) destination)[0] = (cast #bit(U32x4) value)[0]; }

        // Adds per lane with saturation: results clamp to the lane range instead of wrapping.
        func addSaturating(x, y: U8x16)->U8x16 => @vecsatadd(x, y)
        func addSaturating(x, y: S8x16)->S8x16 => @vecsatadd(x, y)
        func addSaturating(x, y: U16x8)->U16x8 => @vecsatadd(x, y)
        func addSaturating(x, y: S16x8)->S16x8 => @vecsatadd(x, y)

        // Subtracts per lane with saturation: results clamp to the lane range instead of wrapping.
        func subSaturating(x, y: U8x16)->U8x16 => @vecsatsub(x, y)
        func subSaturating(x, y: S8x16)->S8x16 => @vecsatsub(x, y)
        func subSaturating(x, y: U16x8)->U16x8 => @vecsatsub(x, y)
        func subSaturating(x, y: S16x8)->S16x8 => @vecsatsub(x, y)

        // Averages per lane with upward rounding: `(x + y + 1) >> 1` without intermediate overflow.
        func average(x, y: U8x16)->U8x16 => @vecavgr(x, y)
        func average(x, y: U16x8)->U16x8 => @vecavgr(x, y)

        // Multiplies 16-bit lanes pairwise and adds each pair of adjacent products into a 32-bit lane.
        func mulAddPairs(x, y: S16x8)->S32x4 => @vecmadd(x, y)

        // Adds every lane into one scalar, with wrapping arithmetic for integers.
        //
        // Adjacent lanes combine first and their results after, so the order is a
        // balanced tree over the lane index. That order is what a float sum observes.
        func sum(value: U8x16)->u8  => @vecreduceadd(value)
        func sum(value: S8x16)->s8  => @vecreduceadd(value)
        func sum(value: U16x8)->u16 => @vecreduceadd(value)
        func sum(value: S16x8)->s16 => @vecreduceadd(value)
        func sum(value: U32x4)->u32 => @vecreduceadd(value)
        func sum(value: S32x4)->s32 => @vecreduceadd(value)
        func sum(value: U64x2)->u64 => @vecreduceadd(value)
        func sum(value: S64x2)->s64 => @vecreduceadd(value)
        func sum(value: F32x4)->f32 => @vecreduceadd(value)
        func sum(value: F64x2)->f64 => @vecreduceadd(value)

        // Returns the smallest lane.
        //
        // Float lanes follow the element-wise [[Math.min]], which answers its second
        // operand when either side is a NaN, so a NaN does not propagate.
        func minimum(value: U8x16)->u8  => @vecreducemin(value)
        func minimum(value: S8x16)->s8  => @vecreducemin(value)
        func minimum(value: U16x8)->u16 => @vecreducemin(value)
        func minimum(value: S16x8)->s16 => @vecreducemin(value)
        func minimum(value: U32x4)->u32 => @vecreducemin(value)
        func minimum(value: S32x4)->s32 => @vecreducemin(value)
        func minimum(value: U64x2)->u64 => @vecreducemin(value)
        func minimum(value: S64x2)->s64 => @vecreducemin(value)
        func minimum(value: F32x4)->f32 => @vecreducemin(value)
        func minimum(value: F64x2)->f64 => @vecreducemin(value)

        // Returns the largest lane, with the NaN behavior of [[Core.Math.Simd.minimum]].
        func maximum(value: U8x16)->u8  => @vecreducemax(value)
        func maximum(value: S8x16)->s8  => @vecreducemax(value)
        func maximum(value: U16x8)->u16 => @vecreducemax(value)
        func maximum(value: S16x8)->s16 => @vecreducemax(value)
        func maximum(value: U32x4)->u32 => @vecreducemax(value)
        func maximum(value: S32x4)->s32 => @vecreducemax(value)
        func maximum(value: U64x2)->u64 => @vecreducemax(value)
        func maximum(value: S64x2)->s64 => @vecreducemax(value)
        func maximum(value: F32x4)->f32 => @vecreducemax(value)
        func maximum(value: F64x2)->f64 => @vecreducemax(value)

        // Combines every lane with a bitwise and.
        func bitwiseAnd(value: U8x16)->u8  => @vecreduceand(value)
        func bitwiseAnd(value: U16x8)->u16 => @vecreduceand(value)
        func bitwiseAnd(value: U32x4)->u32 => @vecreduceand(value)
        func bitwiseAnd(value: U64x2)->u64 => @vecreduceand(value)

        // Combines every lane with a bitwise or.
        func bitwiseOr(value: U8x16)->u8  => @vecreduceor(value)
        func bitwiseOr(value: U16x8)->u16 => @vecreduceor(value)
        func bitwiseOr(value: U32x4)->u32 => @vecreduceor(value)
        func bitwiseOr(value: U64x2)->u64 => @vecreduceor(value)

        // Combines every lane with a bitwise exclusive or.
        func bitwiseXor(value: U8x16)->u8  => @vecreducexor(value)
        func bitwiseXor(value: U16x8)->u16 => @vecreducexor(value)
        func bitwiseXor(value: U32x4)->u32 => @vecreducexor(value)
        func bitwiseXor(value: U64x2)->u64 => @vecreducexor(value)

        // Counts the mask lanes that are all-ones.
        func countTrue(value: U8x16)->u32 => @bitcountnz(@vecmask(value))
        func countTrue(value: U16x8)->u32 => @bitcountnz(@vecmask(value))
        func countTrue(value: U32x4)->u32 => @bitcountnz(@vecmask(value))
        func countTrue(value: U64x2)->u32 => @bitcountnz(@vecmask(value))

        // Sums the absolute differences of the bytes of each half into the low word
        // of the matching 64-bit lane.
        //
        // Signed bytes reach the same instruction by biasing both sides, which leaves
        // the differences unchanged.
        func absoluteDifferences(x, y: U8x16)->U64x2 => @vecsad(x, y)
        func absoluteDifferences(x, y: S8x16)->U64x2 => @vecsad(x, y)

        // Sums the absolute differences of all sixteen bytes.
        func sumAbsoluteDifferences(x, y: U8x16)->u32 => cast(u32) @vecreduceadd(@vecsad(x, y))
        func sumAbsoluteDifferences(x, y: S8x16)->u32 => cast(u32) @vecreduceadd(@vecsad(x, y))

        // Multiplies unsigned and signed bytes pairwise and adds each pair of adjacent
        // products into a 16-bit lane, saturating the sum.
        func mulAddPairs(x: U8x16, y: S8x16)->S16x8 => @vecmaddubs(x, y)

        // Sums every lane into a wider accumulator, which no lane width can overflow.
        func sumWide(value: U8x16)->u32 => cast(u32) @vecreduceadd(@vecsad(value, @vecsplat(0'u8)))
        func sumWide(value: S8x16)->s32 => sumWide(@vecwidenlo(value) + @vecwidenhi(value))
        func sumWide(value: S16x8)->s32 => @vecreduceadd(@vecmadd(value, @vecsplat(1's16)))
        func sumWide(value: U16x8)->u32 => @vecreduceadd(@vecwidenlo(value) + @vecwidenhi(value))
        func sumWide(value: U32x4)->u64 => @vecreduceadd(@vecwidenlo(value) + @vecwidenhi(value))
        func sumWide(value: S32x4)->s64 => @vecreduceadd(@vecwidenlo(value) + @vecwidenhi(value))

        // Converts float lanes to signed 32-bit integers by truncating toward zero.
        //
        // A NaN or a value outside the `s32` range becomes `s32.Min`.
        func truncateToS32(value: F32x4)->S32x4 => @vectruncs32(value)

        // Reads four signed 32-bit values through four unsigned indices.
        //
        // Result lane `i` is `base[indices[i]]`. The caller owns the bounds contract:
        // every index must be at most `s32.Max` and designate a readable element of
        // `base`. AVX2 targets use a hardware gather; portable targets assemble four
        // scalar indexed loads.
        func gather(base: const [*] s32, indices: U32x4)->S32x4 => @vecgather(base, indices)

        // Narrows two vectors into one with unsigned saturation.
        //
        // The lanes of `low` land in the low half of the result and the lanes of `high` in
        // the high half, each clamped to the destination range.
        func packUnsigned(low, high: S16x8)->U8x16 => @vecpackus(low, high)
        func packUnsigned(low, high: S32x4)->U16x8 => @vecpackus(low, high)

        // Narrows two vectors into one with signed saturation.
        //
        // The lanes of `low` land in the low half of the result and the lanes of `high` in
        // the high half, each clamped to the destination range.
        func packSigned(low, high: S16x8)->S8x16 => @vecpackss(low, high)
        func packSigned(low, high: S32x4)->S16x8 => @vecpackss(low, high)

        // Alternates lanes from the low halves of two vectors.
        //
        // The result is `x[0], y[0], x[1], y[1], ...` and discards both high halves.
        func interleaveLow(x, y: U8x16)->U8x16 => @vecinterleavelo(x, y)
        func interleaveLow(x, y: U16x8)->U16x8 => @vecinterleavelo(x, y)
        func interleaveLow(x, y: U32x4)->U32x4 => @vecinterleavelo(x, y)
        func interleaveLow(x, y: U64x2)->U64x2 => @vecinterleavelo(x, y)

        // Alternates lanes from the high halves of two vectors.
        //
        // The result starts at the midpoint of each input and alternates in the same order
        // as [[Core.Math.Simd.interleaveLow]].
        func interleaveHigh(x, y: U8x16)->U8x16 => @vecinterleavehi(x, y)
        func interleaveHigh(x, y: U16x8)->U16x8 => @vecinterleavehi(x, y)
        func interleaveHigh(x, y: U32x4)->U32x4 => @vecinterleavehi(x, y)
        func interleaveHigh(x, y: U64x2)->U64x2 => @vecinterleavehi(x, y)

        // Extends the low half of the lanes to double width, zero-extended for unsigned
        // lanes and sign-extended for signed ones.
        func widenLow(value: U8x16)->U16x8 => @vecwidenlo(value)
        func widenLow(value: S8x16)->S16x8 => @vecwidenlo(value)
        func widenLow(value: U16x8)->U32x4 => @vecwidenlo(value)
        func widenLow(value: S16x8)->S32x4 => @vecwidenlo(value)
        func widenLow(value: U32x4)->U64x2 => @vecwidenlo(value)
        func widenLow(value: S32x4)->S64x2 => @vecwidenlo(value)

        // Extends the high half of the lanes to double width, zero-extended for unsigned
        // lanes and sign-extended for signed ones.
        func widenHigh(value: U8x16)->U16x8 => @vecwidenhi(value)
        func widenHigh(value: S8x16)->S16x8 => @vecwidenhi(value)
        func widenHigh(value: U16x8)->U32x4 => @vecwidenhi(value)
        func widenHigh(value: S16x8)->S32x4 => @vecwidenhi(value)
        func widenHigh(value: U32x4)->U64x2 => @vecwidenhi(value)
        func widenHigh(value: S32x4)->S64x2 => @vecwidenhi(value)

        // Permutes bytes through a dynamic table.
        //
        // Every result byte picks the source byte named by the low four bits of the matching
        // table byte, or zero when the table byte's high bit is set.
        func shuffle(value, table: U8x16)->U8x16 => @vecperm(value, table)

        // Permutes lanes: result lane `i` takes the lane its `pattern` lane names.
        //
        // The index is reduced modulo the lane count, so no pattern is out of range.
        // A pattern known at compile time selects an immediate form where the target
        // has one; one built at run time goes through the dynamic byte permute.
        // [[Core.Math.Simd.shuffle]] is the byte-level form of the same idea.
        func permute(value, pattern: U8x16)->U8x16        => @vecshuffle(value, pattern)
        func permute(value: S8x16, pattern: U8x16)->S8x16 => @vecshuffle(value, pattern)
        func permute(value, pattern: U16x8)->U16x8        => @vecshuffle(value, pattern)
        func permute(value: S16x8, pattern: U16x8)->S16x8 => @vecshuffle(value, pattern)
        func permute(value, pattern: U32x4)->U32x4        => @vecshuffle(value, pattern)
        func permute(value: S32x4, pattern: U32x4)->S32x4 => @vecshuffle(value, pattern)
        func permute(value, pattern: U64x2)->U64x2        => @vecshuffle(value, pattern)
        func permute(value: S64x2, pattern: U64x2)->S64x2 => @vecshuffle(value, pattern)
        func permute(value: F32x4, pattern: U32x4)->F32x4 => @vecshuffle(value, pattern)
        func permute(value: F64x2, pattern: U64x2)->F64x2 => @vecshuffle(value, pattern)

        // Permutes lanes out of two vectors: an index below the lane count reads `x`,
        // and one above it reads `y` at the index minus the lane count.
        func permute2(x, y, pattern: U8x16)->U8x16        => @vecshuffle2(x, y, pattern)
        func permute2(x, y: S8x16, pattern: U8x16)->S8x16 => @vecshuffle2(x, y, pattern)
        func permute2(x, y, pattern: U16x8)->U16x8        => @vecshuffle2(x, y, pattern)
        func permute2(x, y: S16x8, pattern: U16x8)->S16x8 => @vecshuffle2(x, y, pattern)
        func permute2(x, y, pattern: U32x4)->U32x4        => @vecshuffle2(x, y, pattern)
        func permute2(x, y: S32x4, pattern: U32x4)->S32x4 => @vecshuffle2(x, y, pattern)
        func permute2(x, y, pattern: U64x2)->U64x2        => @vecshuffle2(x, y, pattern)
        func permute2(x, y: S64x2, pattern: U64x2)->S64x2 => @vecshuffle2(x, y, pattern)
        func permute2(x, y: F32x4, pattern: U32x4)->F32x4 => @vecshuffle2(x, y, pattern)
        func permute2(x, y: F64x2, pattern: U64x2)->F64x2 => @vecshuffle2(x, y, pattern)

        // Takes sixteen bytes of the concatenation of `low` and `high`, starting at
        // byte `count` of it.
        //
        // A byte past the thirty-two is zero, so a count of 32 or more answers zero.
        func align(low, high: U8x16, count: u8)->U8x16 => @vecalign(low, high, count)
        func align(low, high: U16x8, count: u8)->U16x8 => @vecalign(low, high, count)
        func align(low, high: U32x4, count: u8)->U32x4 => @vecalign(low, high, count)
        func align(low, high: U64x2, count: u8)->U64x2 => @vecalign(low, high, count)
        func align(low, high: F32x4, count: u8)->F32x4 => @vecalign(low, high, count)

        // Collects the even lanes of `x` then those of `y`, undoing one interleave.
        func deinterleaveEven(x, y: U8x16)->U8x16 => @vecshuffle2(x, y, cast(U8x16) [0'u8, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30])
        func deinterleaveEven(x, y: U16x8)->U16x8 => @vecshuffle2(x, y, cast(U16x8) [0'u16, 2, 4, 6, 8, 10, 12, 14])
        func deinterleaveEven(x, y: U32x4)->U32x4 => @vecshuffle2(x, y, cast(U32x4) [0'u32, 2, 4, 6])

        // Collects the odd lanes of `x` then those of `y`.
        func deinterleaveOdd(x, y: U8x16)->U8x16 => @vecshuffle2(x, y, cast(U8x16) [1'u8, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31])
        func deinterleaveOdd(x, y: U16x8)->U16x8 => @vecshuffle2(x, y, cast(U16x8) [1'u16, 3, 5, 7, 9, 11, 13, 15])
        func deinterleaveOdd(x, y: U32x4)->U32x4 => @vecshuffle2(x, y, cast(U32x4) [1'u32, 3, 5, 7])

        // Blends two vectors through a mask: lanes of `ifTrue` where the mask lane is
        // all-ones, lanes of `ifFalse` where it is all-zeros.
        //
        // Comparisons produce exactly such masks, in the unsigned geometry of their operands.
        func select(mask, ifTrue, ifFalse: U8x16)->U8x16        => @vecselect(mask, ifTrue, ifFalse)
        func select(mask: U8x16, ifTrue, ifFalse: S8x16)->S8x16 => @vecselect(mask, ifTrue, ifFalse)
        func select(mask, ifTrue, ifFalse: U16x8)->U16x8        => @vecselect(mask, ifTrue, ifFalse)
        func select(mask: U16x8, ifTrue, ifFalse: S16x8)->S16x8 => @vecselect(mask, ifTrue, ifFalse)
        func select(mask, ifTrue, ifFalse: U32x4)->U32x4        => @vecselect(mask, ifTrue, ifFalse)
        func select(mask: U32x4, ifTrue, ifFalse: S32x4)->S32x4 => @vecselect(mask, ifTrue, ifFalse)
        func select(mask: U32x4, ifTrue, ifFalse: F32x4)->F32x4 => @vecselect(mask, ifTrue, ifFalse)
        func select(mask, ifTrue, ifFalse: U64x2)->U64x2        => @vecselect(mask, ifTrue, ifFalse)
        func select(mask: U64x2, ifTrue, ifFalse: S64x2)->S64x2 => @vecselect(mask, ifTrue, ifFalse)
        func select(mask: U64x2, ifTrue, ifFalse: F64x2)->F64x2 => @vecselect(mask, ifTrue, ifFalse)

        // Gathers the lane sign bits into the low bits of an integer, lane zero in bit zero.
        //
        // On a comparison mask this is one bit per lane, set where the compare held.
        func bitmask(value: U8x16)->u32 => @vecmask(value)
        func bitmask(value: U16x8)->u32 => @vecmask(value)
        func bitmask(value: U32x4)->u32 => @vecmask(value)
        func bitmask(value: U64x2)->u32 => @vecmask(value)

        // Reports whether any mask lane is all-ones.
        func anyTrue(value: U8x16)->bool => @vecany(value)
        func anyTrue(value: U16x8)->bool => @vecany(value)
        func anyTrue(value: U32x4)->bool => @vecany(value)
        func anyTrue(value: U64x2)->bool => @vecany(value)

        // Reports whether every mask lane is all-ones.
        func allTrue(value: U8x16)->bool => @vecall(value)
        func allTrue(value: U16x8)->bool => @vecall(value)
        func allTrue(value: U32x4)->bool => @vecall(value)
        func allTrue(value: U64x2)->bool => @vecall(value)
    }

    // Transposes four rows of four 32-bit lanes in place, through the interleave
    // tree and nothing else: no lane is read or written on its own.
    //
    // The rows are taken in place because an array crosses a call boundary through
    // memory: a form returning a new array would copy the block twice around the
    // eight instructions that do the work.
    #[Inline]
    func transpose4x4(rows: *[4] U32x4)
    {
        // Adjacent rows first, which pairs the lanes.
        let low0  = @vecinterleavelo(rows[][0], rows[][1])
        let low1  = @vecinterleavelo(rows[][2], rows[][3])
        let high0 = @vecinterleavehi(rows[][0], rows[][1])
        let high1 = @vecinterleavehi(rows[][2], rows[][3])

        // Then the same in 64-bit halves, which finishes the transposition.
        let pair0 = cast #bit (U64x2) low0
        let pair1 = cast #bit (U64x2) low1
        let pair2 = cast #bit (U64x2) high0
        let pair3 = cast #bit (U64x2) high1

        rows[][0] = cast #bit (U32x4) @vecinterleavelo(pair0, pair1)
        rows[][1] = cast #bit (U32x4) @vecinterleavehi(pair0, pair1)
        rows[][2] = cast #bit (U32x4) @vecinterleavelo(pair2, pair3)
        rows[][3] = cast #bit (U32x4) @vecinterleavehi(pair2, pair3)
    }

    // Transposes eight rows of eight 16-bit lanes in place, through three
    // interleave rounds and nothing else.
    //
    // The rounds are written out rather than looped: an indexed local array would
    // put every intermediate back in memory, which is what the interleave tree
    // exists to avoid. [[Core.Math.Simd.transpose4x4]] takes its rows in place for
    // the same reason.
    #[Inline]
    func transpose8x8(rows: *[8] U16x8)
    {
        // Adjacent rows first, which pairs the lanes.
        let word0 = @vecinterleavelo(rows[][0], rows[][1])
        let word1 = @vecinterleavelo(rows[][2], rows[][3])
        let word2 = @vecinterleavelo(rows[][4], rows[][5])
        let word3 = @vecinterleavelo(rows[][6], rows[][7])
        let word4 = @vecinterleavehi(rows[][0], rows[][1])
        let word5 = @vecinterleavehi(rows[][2], rows[][3])
        let word6 = @vecinterleavehi(rows[][4], rows[][5])
        let word7 = @vecinterleavehi(rows[][6], rows[][7])

        // Then in 32-bit groups, which brings the lanes together four by four.
        let quad0 = @vecinterleavelo(cast #bit (U32x4) word0, cast #bit (U32x4) word1)
        let quad1 = @vecinterleavehi(cast #bit (U32x4) word0, cast #bit (U32x4) word1)
        let quad2 = @vecinterleavelo(cast #bit (U32x4) word2, cast #bit (U32x4) word3)
        let quad3 = @vecinterleavehi(cast #bit (U32x4) word2, cast #bit (U32x4) word3)
        let quad4 = @vecinterleavelo(cast #bit (U32x4) word4, cast #bit (U32x4) word5)
        let quad5 = @vecinterleavehi(cast #bit (U32x4) word4, cast #bit (U32x4) word5)
        let quad6 = @vecinterleavelo(cast #bit (U32x4) word6, cast #bit (U32x4) word7)
        let quad7 = @vecinterleavehi(cast #bit (U32x4) word6, cast #bit (U32x4) word7)

        // And a last round in 64-bit halves.
        rows[][0] = cast #bit (U16x8) @vecinterleavelo(cast #bit (U64x2) quad0, cast #bit (U64x2) quad2)
        rows[][1] = cast #bit (U16x8) @vecinterleavehi(cast #bit (U64x2) quad0, cast #bit (U64x2) quad2)
        rows[][2] = cast #bit (U16x8) @vecinterleavelo(cast #bit (U64x2) quad1, cast #bit (U64x2) quad3)
        rows[][3] = cast #bit (U16x8) @vecinterleavehi(cast #bit (U64x2) quad1, cast #bit (U64x2) quad3)
        rows[][4] = cast #bit (U16x8) @vecinterleavelo(cast #bit (U64x2) quad4, cast #bit (U64x2) quad6)
        rows[][5] = cast #bit (U16x8) @vecinterleavehi(cast #bit (U64x2) quad4, cast #bit (U64x2) quad6)
        rows[][6] = cast #bit (U16x8) @vecinterleavelo(cast #bit (U64x2) quad5, cast #bit (U64x2) quad7)
        rows[][7] = cast #bit (U16x8) @vecinterleavehi(cast #bit (U64x2) quad5, cast #bit (U64x2) quad7)
    }
}

// The element-wise vector forms of the scalar functions of this namespace. [[Math.min]]
// and [[Math.max]] need no dedicated overloads: their generic forms accept the vector
// types directly.
#[Inline]
{
    // Returns the absolute value, per lane.
    func abs(x: Simd.S8x16)->Simd.S8x16 => @abs(x)
    func abs(x: Simd.S16x8)->Simd.S16x8 => @abs(x)
    func abs(x: Simd.S32x4)->Simd.S32x4 => @abs(x)
    func abs(x: Simd.S64x2)->Simd.S64x2 => @abs(x)

    // Returns the absolute value, per lane, by clearing the sign bit.
    //
    // A NaN keeps its payload and a negative zero becomes a positive one.
    func abs(x: Simd.F32x4)->Simd.F32x4 => @abs(x)
    func abs(x: Simd.F64x2)->Simd.F64x2 => @abs(x)

    // Returns the square root, per lane.
    func sqrt(x: Simd.F32x4)->Simd.F32x4 => @sqrt(x)
    func sqrt(x: Simd.F64x2)->Simd.F64x2 => @sqrt(x)

    // Multiplies two values and adds a third, per lane.
    func mulAdd(x, y, z: Simd.F32x4)->Simd.F32x4 => @muladd(x, y, z)
    func mulAdd(x, y, z: Simd.F64x2)->Simd.F64x2 => @muladd(x, y, z)

    // Rounds downward to an integer-valued number, per lane.
    func floor(x: Simd.F32x4)->Simd.F32x4 => @floor(x)
    func floor(x: Simd.F64x2)->Simd.F64x2 => @floor(x)

    // Rounds upward to an integer-valued number, per lane.
    func ceil(x: Simd.F32x4)->Simd.F32x4 => @ceil(x)
    func ceil(x: Simd.F64x2)->Simd.F64x2 => @ceil(x)

    // Removes the fractional part, per lane.
    func trunc(x: Simd.F32x4)->Simd.F32x4 => @trunc(x)
    func trunc(x: Simd.F64x2)->Simd.F64x2 => @trunc(x)

    // Rotates the bits of every lane left by `y`, taken modulo the lane width.
    func rol(x: Simd.U8x16, y: u8)->Simd.U8x16 => @rol(x, y)
    func rol(x: Simd.U16x8, y: u8)->Simd.U16x8 => @rol(x, y)
    func rol(x: Simd.U32x4, y: u8)->Simd.U32x4 => @rol(x, y)
    func rol(x: Simd.U64x2, y: u8)->Simd.U64x2 => @rol(x, y)

    // Rotates the bits of every lane right by `y`, taken modulo the lane width.
    func ror(x: Simd.U8x16, y: u8)->Simd.U8x16 => @ror(x, y)
    func ror(x: Simd.U16x8, y: u8)->Simd.U16x8 => @ror(x, y)
    func ror(x: Simd.U32x4, y: u8)->Simd.U32x4 => @ror(x, y)
    func ror(x: Simd.U64x2, y: u8)->Simd.U64x2 => @ror(x, y)

    // Returns the number of bits set to one, per lane.
    func countOnes(x: Simd.U8x16)->Simd.U8x16 => @bitcountnz(x)
    func countOnes(x: Simd.U16x8)->Simd.U16x8 => @bitcountnz(x)
    func countOnes(x: Simd.U32x4)->Simd.U32x4 => @bitcountnz(x)
    func countOnes(x: Simd.U64x2)->Simd.U64x2 => @bitcountnz(x)

    // Returns the number of zero bits above the highest set bit, per lane.
    //
    // An all-zero lane answers the lane width.
    func leadingZeros(x: Simd.U8x16)->Simd.U8x16 => @bitcountlz(x)
    func leadingZeros(x: Simd.U16x8)->Simd.U16x8 => @bitcountlz(x)
    func leadingZeros(x: Simd.U32x4)->Simd.U32x4 => @bitcountlz(x)
    func leadingZeros(x: Simd.U64x2)->Simd.U64x2 => @bitcountlz(x)

    // Returns the number of zero bits below the lowest set bit, per lane.
    //
    // An all-zero lane answers the lane width.
    func trailingZeros(x: Simd.U8x16)->Simd.U8x16 => @bitcounttz(x)
    func trailingZeros(x: Simd.U16x8)->Simd.U16x8 => @bitcounttz(x)
    func trailingZeros(x: Simd.U32x4)->Simd.U32x4 => @bitcounttz(x)
    func trailingZeros(x: Simd.U64x2)->Simd.U64x2 => @bitcounttz(x)

    // Reverses the bytes inside every lane.
    func byteswap(x: Simd.U16x8)->Simd.U16x8 => @byteswap(x)
    func byteswap(x: Simd.U32x4)->Simd.U32x4 => @byteswap(x)
    func byteswap(x: Simd.U64x2)->Simd.U64x2 => @byteswap(x)

    // Returns the magnitude of `x` carrying the sign of `y`, per lane.
    //
    // Only the sign bit moves, so a NaN keeps its payload and a zero takes the
    // sign it is given.
    func copysign(x, y: Simd.F32x4)->Simd.F32x4
    {
        const Magnitude = @vecsplat(0x7FFF_FFFF'u32)
        const Sign      = @vecsplat(0x8000_0000'u32)
        return cast #bit (Simd.F32x4) ((cast #bit (Simd.U32x4) x & Magnitude) | (cast #bit (Simd.U32x4) y & Sign))
    }

    func copysign(x, y: Simd.F64x2)->Simd.F64x2
    {
        const Magnitude = @vecsplat(0x7FFF_FFFF_FFFF_FFFF'u64)
        const Sign      = @vecsplat(0x8000_0000_0000_0000'u64)
        return cast #bit (Simd.F64x2) ((cast #bit (Simd.U64x2) x & Magnitude) | (cast #bit (Simd.U64x2) y & Sign))
    }

    // Returns the sign of every lane.
    //
    // A lane below zero answers -1 and a lane above it 1; zero and a NaN both
    // answer 0.
    func sign(x: Simd.F32x4)->Simd.F32x4
    {
        let zero     = @vecsplat(0'f32)
        let one      = @vecsplat(1'f32)
        let positive = Simd.select(x > zero, one, zero)
        let negative = Simd.select(x < zero, one, zero)
        return positive - negative
    }

    func sign(x: Simd.F64x2)->Simd.F64x2
    {
        let zero     = @vecsplat(0'f64)
        let one      = @vecsplat(1'f64)
        let positive = Simd.select(x > zero, one, zero)
        let negative = Simd.select(x < zero, one, zero)
        return positive - negative
    }

    // Clamps every lane between zero and one.
    func saturate(x: Simd.F32x4)->Simd.F32x4 => clamp(x, @vecsplat(0'f32), @vecsplat(1'f32))
    func saturate(x: Simd.F64x2)->Simd.F64x2 => clamp(x, @vecsplat(0'f64), @vecsplat(1'f64))

    // Interpolates linearly between `x` and `y`, per lane.
    func lerp(x, y, factor: Simd.F32x4)->Simd.F32x4 => x + factor * (y - x)
    func lerp(x, y, factor: Simd.F64x2)->Simd.F64x2 => x + factor * (y - x)
}
