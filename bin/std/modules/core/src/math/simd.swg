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
        func splat(value: u8)->U8x16  => Swag.vecsplat(value)
        func splat(value: s8)->S8x16  => Swag.vecsplat(value)
        func splat(value: u16)->U16x8 => Swag.vecsplat(value)
        func splat(value: s16)->S16x8 => Swag.vecsplat(value)
        func splat(value: u32)->U32x4 => Swag.vecsplat(value)
        func splat(value: s32)->S32x4 => Swag.vecsplat(value)
        func splat(value: u64)->U64x2 => Swag.vecsplat(value)
        func splat(value: s64)->S64x2 => Swag.vecsplat(value)
        func splat(value: f32)->F32x4 => Swag.vecsplat(value)
        func splat(value: f64)->F64x2 => Swag.vecsplat(value)

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
        func addSaturating(x, y: U8x16)->U8x16 => Swag.vecsatadd(x, y)
        func addSaturating(x, y: S8x16)->S8x16 => Swag.vecsatadd(x, y)
        func addSaturating(x, y: U16x8)->U16x8 => Swag.vecsatadd(x, y)
        func addSaturating(x, y: S16x8)->S16x8 => Swag.vecsatadd(x, y)

        // Subtracts per lane with saturation: results clamp to the lane range instead of wrapping.
        func subSaturating(x, y: U8x16)->U8x16 => Swag.vecsatsub(x, y)
        func subSaturating(x, y: S8x16)->S8x16 => Swag.vecsatsub(x, y)
        func subSaturating(x, y: U16x8)->U16x8 => Swag.vecsatsub(x, y)
        func subSaturating(x, y: S16x8)->S16x8 => Swag.vecsatsub(x, y)

        // Averages per lane with upward rounding: `(x + y + 1) >> 1` without intermediate overflow.
        func average(x, y: U8x16)->U8x16 => Swag.vecavgr(x, y)
        func average(x, y: U16x8)->U16x8 => Swag.vecavgr(x, y)

        // Multiplies 16-bit lanes pairwise and adds each pair of adjacent products into a 32-bit lane.
        func mulAddPairs(x, y: S16x8)->S32x4 => Swag.vecmadd(x, y)

        // The half of a lane product that `*` drops: the bits above the lane width.
        //
        // With the low half from `*`, the two are the whole product, and
        // [[Core.Math.Simd.mulWidenLow]] puts them back together.
        func mulHigh(x, y: U8x16)->U8x16 => Swag.vecmulhi(x, y)
        func mulHigh(x, y: S8x16)->S8x16 => Swag.vecmulhi(x, y)
        func mulHigh(x, y: U16x8)->U16x8 => Swag.vecmulhi(x, y)
        func mulHigh(x, y: S16x8)->S16x8 => Swag.vecmulhi(x, y)
        func mulHigh(x, y: U32x4)->U32x4 => Swag.vecmulhi(x, y)
        func mulHigh(x, y: S32x4)->S32x4 => Swag.vecmulhi(x, y)
        func mulHigh(x, y: U64x2)->U64x2 => Swag.vecmulhi(x, y)
        func mulHigh(x, y: S64x2)->S64x2 => Swag.vecmulhi(x, y)

        // The exact products of the low half of the lanes, in lanes twice as wide.
        //
        // Nothing is lost: the low and high halves of each product interleave back
        // into the double-width lane they belong to.
        func mulWidenLow(x, y: U8x16)->U16x8 => cast #bit (U16x8) Swag.vecinterleavelo(x * y, Swag.vecmulhi(x, y))
        func mulWidenLow(x, y: S8x16)->S16x8 => cast #bit (S16x8) Swag.vecinterleavelo(cast #bit (U8x16) (x * y), cast #bit (U8x16) Swag.vecmulhi(x, y))
        func mulWidenLow(x, y: U16x8)->U32x4 => cast #bit (U32x4) Swag.vecinterleavelo(x * y, Swag.vecmulhi(x, y))
        func mulWidenLow(x, y: S16x8)->S32x4 => cast #bit (S32x4) Swag.vecinterleavelo(cast #bit (U16x8) (x * y), cast #bit (U16x8) Swag.vecmulhi(x, y))
        func mulWidenLow(x, y: U32x4)->U64x2 => cast #bit (U64x2) Swag.vecinterleavelo(x * y, Swag.vecmulhi(x, y))
        func mulWidenLow(x, y: S32x4)->S64x2 => cast #bit (S64x2) Swag.vecinterleavelo(cast #bit (U32x4) (x * y), cast #bit (U32x4) Swag.vecmulhi(x, y))

        // The same for the high half of the lanes.
        func mulWidenHigh(x, y: U8x16)->U16x8 => cast #bit (U16x8) Swag.vecinterleavehi(x * y, Swag.vecmulhi(x, y))
        func mulWidenHigh(x, y: S8x16)->S16x8 => cast #bit (S16x8) Swag.vecinterleavehi(cast #bit (U8x16) (x * y), cast #bit (U8x16) Swag.vecmulhi(x, y))
        func mulWidenHigh(x, y: U16x8)->U32x4 => cast #bit (U32x4) Swag.vecinterleavehi(x * y, Swag.vecmulhi(x, y))
        func mulWidenHigh(x, y: S16x8)->S32x4 => cast #bit (S32x4) Swag.vecinterleavehi(cast #bit (U16x8) (x * y), cast #bit (U16x8) Swag.vecmulhi(x, y))
        func mulWidenHigh(x, y: U32x4)->U64x2 => cast #bit (U64x2) Swag.vecinterleavehi(x * y, Swag.vecmulhi(x, y))
        func mulWidenHigh(x, y: S32x4)->S64x2 => cast #bit (S64x2) Swag.vecinterleavehi(cast #bit (U32x4) (x * y), cast #bit (U32x4) Swag.vecmulhi(x, y))

        // Adds every lane into one scalar, with wrapping arithmetic for integers.
        //
        // Adjacent lanes combine first and their results after, so the order is a
        // balanced tree over the lane index. That order is what a float sum observes.
        func sum(value: U8x16)->u8  => Swag.vecreduceadd(value)
        func sum(value: S8x16)->s8  => Swag.vecreduceadd(value)
        func sum(value: U16x8)->u16 => Swag.vecreduceadd(value)
        func sum(value: S16x8)->s16 => Swag.vecreduceadd(value)
        func sum(value: U32x4)->u32 => Swag.vecreduceadd(value)
        func sum(value: S32x4)->s32 => Swag.vecreduceadd(value)
        func sum(value: U64x2)->u64 => Swag.vecreduceadd(value)
        func sum(value: S64x2)->s64 => Swag.vecreduceadd(value)
        func sum(value: F32x4)->f32 => Swag.vecreduceadd(value)
        func sum(value: F64x2)->f64 => Swag.vecreduceadd(value)

        // Returns the smallest lane.
        //
        // Float lanes follow the element-wise [[Math.min]], which answers its second
        // operand when either side is a NaN, so a NaN does not propagate.
        func minimum(value: U8x16)->u8  => Swag.vecreducemin(value)
        func minimum(value: S8x16)->s8  => Swag.vecreducemin(value)
        func minimum(value: U16x8)->u16 => Swag.vecreducemin(value)
        func minimum(value: S16x8)->s16 => Swag.vecreducemin(value)
        func minimum(value: U32x4)->u32 => Swag.vecreducemin(value)
        func minimum(value: S32x4)->s32 => Swag.vecreducemin(value)
        func minimum(value: U64x2)->u64 => Swag.vecreducemin(value)
        func minimum(value: S64x2)->s64 => Swag.vecreducemin(value)
        func minimum(value: F32x4)->f32 => Swag.vecreducemin(value)
        func minimum(value: F64x2)->f64 => Swag.vecreducemin(value)

        // Returns the largest lane, with the NaN behavior of [[Core.Math.Simd.minimum]].
        func maximum(value: U8x16)->u8  => Swag.vecreducemax(value)
        func maximum(value: S8x16)->s8  => Swag.vecreducemax(value)
        func maximum(value: U16x8)->u16 => Swag.vecreducemax(value)
        func maximum(value: S16x8)->s16 => Swag.vecreducemax(value)
        func maximum(value: U32x4)->u32 => Swag.vecreducemax(value)
        func maximum(value: S32x4)->s32 => Swag.vecreducemax(value)
        func maximum(value: U64x2)->u64 => Swag.vecreducemax(value)
        func maximum(value: S64x2)->s64 => Swag.vecreducemax(value)
        func maximum(value: F32x4)->f32 => Swag.vecreducemax(value)
        func maximum(value: F64x2)->f64 => Swag.vecreducemax(value)

        // Combines every lane with a bitwise and.
        func bitwiseAnd(value: U8x16)->u8  => Swag.vecreduceand(value)
        func bitwiseAnd(value: U16x8)->u16 => Swag.vecreduceand(value)
        func bitwiseAnd(value: U32x4)->u32 => Swag.vecreduceand(value)
        func bitwiseAnd(value: U64x2)->u64 => Swag.vecreduceand(value)

        // Combines every lane with a bitwise or.
        func bitwiseOr(value: U8x16)->u8  => Swag.vecreduceor(value)
        func bitwiseOr(value: U16x8)->u16 => Swag.vecreduceor(value)
        func bitwiseOr(value: U32x4)->u32 => Swag.vecreduceor(value)
        func bitwiseOr(value: U64x2)->u64 => Swag.vecreduceor(value)

        // Combines every lane with a bitwise exclusive or.
        func bitwiseXor(value: U8x16)->u8  => Swag.vecreducexor(value)
        func bitwiseXor(value: U16x8)->u16 => Swag.vecreducexor(value)
        func bitwiseXor(value: U32x4)->u32 => Swag.vecreducexor(value)
        func bitwiseXor(value: U64x2)->u64 => Swag.vecreducexor(value)

        // Counts the mask lanes that are all-ones.
        func countTrue(value: U8x16)->u32 => Swag.bitCountNz(Swag.vecmask(value))
        func countTrue(value: U16x8)->u32 => Swag.bitCountNz(Swag.vecmask(value))
        func countTrue(value: U32x4)->u32 => Swag.bitCountNz(Swag.vecmask(value))
        func countTrue(value: U64x2)->u32 => Swag.bitCountNz(Swag.vecmask(value))

        // Sums the absolute differences of the bytes of each half into the low word
        // of the matching 64-bit lane.
        //
        // Signed bytes reach the same instruction by biasing both sides, which leaves
        // the differences unchanged.
        func absoluteDifferences(x, y: U8x16)->U64x2 => Swag.vecsad(x, y)
        func absoluteDifferences(x, y: S8x16)->U64x2 => Swag.vecsad(x, y)

        // Sums the absolute differences of all sixteen bytes.
        func sumAbsoluteDifferences(x, y: U8x16)->u32 => cast(u32) Swag.vecreduceadd(Swag.vecsad(x, y))
        func sumAbsoluteDifferences(x, y: S8x16)->u32 => cast(u32) Swag.vecreduceadd(Swag.vecsad(x, y))

        // Multiplies unsigned and signed bytes pairwise and adds each pair of adjacent
        // products into a 16-bit lane, saturating the sum.
        func mulAddPairs(x: U8x16, y: S8x16)->S16x8 => Swag.vecmaddubs(x, y)

        // Sums every lane into a wider accumulator, which no lane width can overflow.
        func sumWide(value: U8x16)->u32 => cast(u32) Swag.vecreduceadd(Swag.vecsad(value, Swag.vecsplat(0'u8)))
        func sumWide(value: S8x16)->s32 => sumWide(Swag.vecwidenlo(value) + Swag.vecwidenhi(value))
        func sumWide(value: S16x8)->s32 => Swag.vecreduceadd(Swag.vecmadd(value, Swag.vecsplat(1's16)))
        func sumWide(value: U16x8)->u32 => Swag.vecreduceadd(Swag.vecwidenlo(value) + Swag.vecwidenhi(value))
        func sumWide(value: U32x4)->u64 => Swag.vecreduceadd(Swag.vecwidenlo(value) + Swag.vecwidenhi(value))
        func sumWide(value: S32x4)->s64 => Swag.vecreduceadd(Swag.vecwidenlo(value) + Swag.vecwidenhi(value))

        // Converts float lanes to signed 32-bit integers by truncating toward zero.
        //
        // A NaN or a value outside the `s32` range becomes `s32.Min`.
        func truncateToS32(value: F32x4)->S32x4 => Swag.vectruncs32(value)

        // Reads four signed 32-bit values through four unsigned indices.
        //
        // Result lane `i` is `base[indices[i]]`. The caller owns the bounds contract:
        // every index must be at most `s32.Max` and designate a readable element of
        // `base`. AVX2 targets use a hardware gather; portable targets assemble four
        // scalar indexed loads.
        func gather(base: const [*] s32, indices: U32x4)->S32x4 => Swag.vecgather(base, indices)

        // Narrows two vectors into one with unsigned saturation.
        //
        // The lanes of `low` land in the low half of the result and the lanes of `high` in
        // the high half, each clamped to the destination range.
        func packUnsigned(low, high: S16x8)->U8x16 => Swag.vecpackus(low, high)
        func packUnsigned(low, high: S32x4)->U16x8 => Swag.vecpackus(low, high)

        // Narrows two vectors into one with signed saturation.
        //
        // The lanes of `low` land in the low half of the result and the lanes of `high` in
        // the high half, each clamped to the destination range.
        func packSigned(low, high: S16x8)->S8x16 => Swag.vecpackss(low, high)
        func packSigned(low, high: S32x4)->S16x8 => Swag.vecpackss(low, high)

        // Alternates lanes from the low halves of two vectors.
        //
        // The result is `x[0], y[0], x[1], y[1], ...` and discards both high halves.
        func interleaveLow(x, y: U8x16)->U8x16 => Swag.vecinterleavelo(x, y)
        func interleaveLow(x, y: U16x8)->U16x8 => Swag.vecinterleavelo(x, y)
        func interleaveLow(x, y: U32x4)->U32x4 => Swag.vecinterleavelo(x, y)
        func interleaveLow(x, y: U64x2)->U64x2 => Swag.vecinterleavelo(x, y)

        // Alternates lanes from the high halves of two vectors.
        //
        // The result starts at the midpoint of each input and alternates in the same order
        // as [[Core.Math.Simd.interleaveLow]].
        func interleaveHigh(x, y: U8x16)->U8x16 => Swag.vecinterleavehi(x, y)
        func interleaveHigh(x, y: U16x8)->U16x8 => Swag.vecinterleavehi(x, y)
        func interleaveHigh(x, y: U32x4)->U32x4 => Swag.vecinterleavehi(x, y)
        func interleaveHigh(x, y: U64x2)->U64x2 => Swag.vecinterleavehi(x, y)

        // Extends the low half of the lanes to double width, zero-extended for unsigned
        // lanes and sign-extended for signed ones.
        func widenLow(value: U8x16)->U16x8 => Swag.vecwidenlo(value)
        func widenLow(value: S8x16)->S16x8 => Swag.vecwidenlo(value)
        func widenLow(value: U16x8)->U32x4 => Swag.vecwidenlo(value)
        func widenLow(value: S16x8)->S32x4 => Swag.vecwidenlo(value)
        func widenLow(value: U32x4)->U64x2 => Swag.vecwidenlo(value)
        func widenLow(value: S32x4)->S64x2 => Swag.vecwidenlo(value)

        // Extends the high half of the lanes to double width, zero-extended for unsigned
        // lanes and sign-extended for signed ones.
        func widenHigh(value: U8x16)->U16x8 => Swag.vecwidenhi(value)
        func widenHigh(value: S8x16)->S16x8 => Swag.vecwidenhi(value)
        func widenHigh(value: U16x8)->U32x4 => Swag.vecwidenhi(value)
        func widenHigh(value: S16x8)->S32x4 => Swag.vecwidenhi(value)
        func widenHigh(value: U32x4)->U64x2 => Swag.vecwidenhi(value)
        func widenHigh(value: S32x4)->S64x2 => Swag.vecwidenhi(value)

        // Permutes bytes through a dynamic table.
        //
        // Every result byte picks the source byte named by the low four bits of the matching
        // table byte, or zero when the table byte's high bit is set.
        func shuffle(value, table: U8x16)->U8x16 => Swag.vecperm(value, table)

        // Permutes lanes: result lane `i` takes the lane its `pattern` lane names.
        //
        // The index is reduced modulo the lane count, so no pattern is out of range.
        // A pattern known at compile time selects an immediate form where the target
        // has one; one built at run time goes through the dynamic byte permute.
        // [[Core.Math.Simd.shuffle]] is the byte-level form of the same idea.
        func permute(value, pattern: U8x16)->U8x16        => Swag.vecshuffle(value, pattern)
        func permute(value: S8x16, pattern: U8x16)->S8x16 => Swag.vecshuffle(value, pattern)
        func permute(value, pattern: U16x8)->U16x8        => Swag.vecshuffle(value, pattern)
        func permute(value: S16x8, pattern: U16x8)->S16x8 => Swag.vecshuffle(value, pattern)
        func permute(value, pattern: U32x4)->U32x4        => Swag.vecshuffle(value, pattern)
        func permute(value: S32x4, pattern: U32x4)->S32x4 => Swag.vecshuffle(value, pattern)
        func permute(value, pattern: U64x2)->U64x2        => Swag.vecshuffle(value, pattern)
        func permute(value: S64x2, pattern: U64x2)->S64x2 => Swag.vecshuffle(value, pattern)
        func permute(value: F32x4, pattern: U32x4)->F32x4 => Swag.vecshuffle(value, pattern)
        func permute(value: F64x2, pattern: U64x2)->F64x2 => Swag.vecshuffle(value, pattern)

        // Permutes lanes out of two vectors: an index below the lane count reads `x`,
        // and one above it reads `y` at the index minus the lane count.
        func permute2(x, y, pattern: U8x16)->U8x16        => Swag.vecshuffle2(x, y, pattern)
        func permute2(x, y: S8x16, pattern: U8x16)->S8x16 => Swag.vecshuffle2(x, y, pattern)
        func permute2(x, y, pattern: U16x8)->U16x8        => Swag.vecshuffle2(x, y, pattern)
        func permute2(x, y: S16x8, pattern: U16x8)->S16x8 => Swag.vecshuffle2(x, y, pattern)
        func permute2(x, y, pattern: U32x4)->U32x4        => Swag.vecshuffle2(x, y, pattern)
        func permute2(x, y: S32x4, pattern: U32x4)->S32x4 => Swag.vecshuffle2(x, y, pattern)
        func permute2(x, y, pattern: U64x2)->U64x2        => Swag.vecshuffle2(x, y, pattern)
        func permute2(x, y: S64x2, pattern: U64x2)->S64x2 => Swag.vecshuffle2(x, y, pattern)
        func permute2(x, y: F32x4, pattern: U32x4)->F32x4 => Swag.vecshuffle2(x, y, pattern)
        func permute2(x, y: F64x2, pattern: U64x2)->F64x2 => Swag.vecshuffle2(x, y, pattern)

        // Takes sixteen bytes of the concatenation of `low` and `high`, starting at
        // byte `count` of it.
        //
        // A byte past the thirty-two is zero, so a count of 32 or more answers zero.
        func align(low, high: U8x16, count: u8)->U8x16 => Swag.vecalign(low, high, count)
        func align(low, high: U16x8, count: u8)->U16x8 => Swag.vecalign(low, high, count)
        func align(low, high: U32x4, count: u8)->U32x4 => Swag.vecalign(low, high, count)
        func align(low, high: U64x2, count: u8)->U64x2 => Swag.vecalign(low, high, count)
        func align(low, high: F32x4, count: u8)->F32x4 => Swag.vecalign(low, high, count)

        // Collects the even lanes of `x` then those of `y`, undoing one interleave.
        func deinterleaveEven(x, y: U8x16)->U8x16 => Swag.vecshuffle2(x, y, cast(U8x16) [0'u8, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30])
        func deinterleaveEven(x, y: U16x8)->U16x8 => Swag.vecshuffle2(x, y, cast(U16x8) [0'u16, 2, 4, 6, 8, 10, 12, 14])
        func deinterleaveEven(x, y: U32x4)->U32x4 => Swag.vecshuffle2(x, y, cast(U32x4) [0'u32, 2, 4, 6])

        // Collects the odd lanes of `x` then those of `y`.
        func deinterleaveOdd(x, y: U8x16)->U8x16 => Swag.vecshuffle2(x, y, cast(U8x16) [1'u8, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31])
        func deinterleaveOdd(x, y: U16x8)->U16x8 => Swag.vecshuffle2(x, y, cast(U16x8) [1'u16, 3, 5, 7, 9, 11, 13, 15])
        func deinterleaveOdd(x, y: U32x4)->U32x4 => Swag.vecshuffle2(x, y, cast(U32x4) [1'u32, 3, 5, 7])

        // Blends two vectors through a mask: lanes of `ifTrue` where the mask lane is
        // all-ones, lanes of `ifFalse` where it is all-zeros.
        //
        // Comparisons produce exactly such masks, in the unsigned geometry of their operands.
        func select(mask, ifTrue, ifFalse: U8x16)->U8x16        => Swag.vecselect(mask, ifTrue, ifFalse)
        func select(mask: U8x16, ifTrue, ifFalse: S8x16)->S8x16 => Swag.vecselect(mask, ifTrue, ifFalse)
        func select(mask, ifTrue, ifFalse: U16x8)->U16x8        => Swag.vecselect(mask, ifTrue, ifFalse)
        func select(mask: U16x8, ifTrue, ifFalse: S16x8)->S16x8 => Swag.vecselect(mask, ifTrue, ifFalse)
        func select(mask, ifTrue, ifFalse: U32x4)->U32x4        => Swag.vecselect(mask, ifTrue, ifFalse)
        func select(mask: U32x4, ifTrue, ifFalse: S32x4)->S32x4 => Swag.vecselect(mask, ifTrue, ifFalse)
        func select(mask: U32x4, ifTrue, ifFalse: F32x4)->F32x4 => Swag.vecselect(mask, ifTrue, ifFalse)
        func select(mask, ifTrue, ifFalse: U64x2)->U64x2        => Swag.vecselect(mask, ifTrue, ifFalse)
        func select(mask: U64x2, ifTrue, ifFalse: S64x2)->S64x2 => Swag.vecselect(mask, ifTrue, ifFalse)
        func select(mask: U64x2, ifTrue, ifFalse: F64x2)->F64x2 => Swag.vecselect(mask, ifTrue, ifFalse)

        // Gathers the lane sign bits into the low bits of an integer, lane zero in bit zero.
        //
        // On a comparison mask this is one bit per lane, set where the compare held.
        func bitmask(value: U8x16)->u32 => Swag.vecmask(value)
        func bitmask(value: U16x8)->u32 => Swag.vecmask(value)
        func bitmask(value: U32x4)->u32 => Swag.vecmask(value)
        func bitmask(value: U64x2)->u32 => Swag.vecmask(value)

        // Reports whether any mask lane is all-ones.
        func anyTrue(value: U8x16)->bool => Swag.vecany(value)
        func anyTrue(value: U16x8)->bool => Swag.vecany(value)
        func anyTrue(value: U32x4)->bool => Swag.vecany(value)
        func anyTrue(value: U64x2)->bool => Swag.vecany(value)

        // Reports whether every mask lane is all-ones.
        func allTrue(value: U8x16)->bool => Swag.vecall(value)
        func allTrue(value: U16x8)->bool => Swag.vecall(value)
        func allTrue(value: U32x4)->bool => Swag.vecall(value)
        func allTrue(value: U64x2)->bool => Swag.vecall(value)
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
        let low0  = Swag.vecinterleavelo(rows[][0], rows[][1])
        let low1  = Swag.vecinterleavelo(rows[][2], rows[][3])
        let high0 = Swag.vecinterleavehi(rows[][0], rows[][1])
        let high1 = Swag.vecinterleavehi(rows[][2], rows[][3])

        // Then the same in 64-bit halves, which finishes the transposition.
        let pair0 = cast #bit (U64x2) low0
        let pair1 = cast #bit (U64x2) low1
        let pair2 = cast #bit (U64x2) high0
        let pair3 = cast #bit (U64x2) high1

        rows[][0] = cast #bit (U32x4) Swag.vecinterleavelo(pair0, pair1)
        rows[][1] = cast #bit (U32x4) Swag.vecinterleavehi(pair0, pair1)
        rows[][2] = cast #bit (U32x4) Swag.vecinterleavelo(pair2, pair3)
        rows[][3] = cast #bit (U32x4) Swag.vecinterleavehi(pair2, pair3)
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
        let word0 = Swag.vecinterleavelo(rows[][0], rows[][1])
        let word1 = Swag.vecinterleavelo(rows[][2], rows[][3])
        let word2 = Swag.vecinterleavelo(rows[][4], rows[][5])
        let word3 = Swag.vecinterleavelo(rows[][6], rows[][7])
        let word4 = Swag.vecinterleavehi(rows[][0], rows[][1])
        let word5 = Swag.vecinterleavehi(rows[][2], rows[][3])
        let word6 = Swag.vecinterleavehi(rows[][4], rows[][5])
        let word7 = Swag.vecinterleavehi(rows[][6], rows[][7])

        // Then in 32-bit groups, which brings the lanes together four by four.
        let quad0 = Swag.vecinterleavelo(cast #bit (U32x4) word0, cast #bit (U32x4) word1)
        let quad1 = Swag.vecinterleavehi(cast #bit (U32x4) word0, cast #bit (U32x4) word1)
        let quad2 = Swag.vecinterleavelo(cast #bit (U32x4) word2, cast #bit (U32x4) word3)
        let quad3 = Swag.vecinterleavehi(cast #bit (U32x4) word2, cast #bit (U32x4) word3)
        let quad4 = Swag.vecinterleavelo(cast #bit (U32x4) word4, cast #bit (U32x4) word5)
        let quad5 = Swag.vecinterleavehi(cast #bit (U32x4) word4, cast #bit (U32x4) word5)
        let quad6 = Swag.vecinterleavelo(cast #bit (U32x4) word6, cast #bit (U32x4) word7)
        let quad7 = Swag.vecinterleavehi(cast #bit (U32x4) word6, cast #bit (U32x4) word7)

        // And a last round in 64-bit halves.
        rows[][0] = cast #bit (U16x8) Swag.vecinterleavelo(cast #bit (U64x2) quad0, cast #bit (U64x2) quad2)
        rows[][1] = cast #bit (U16x8) Swag.vecinterleavehi(cast #bit (U64x2) quad0, cast #bit (U64x2) quad2)
        rows[][2] = cast #bit (U16x8) Swag.vecinterleavelo(cast #bit (U64x2) quad1, cast #bit (U64x2) quad3)
        rows[][3] = cast #bit (U16x8) Swag.vecinterleavehi(cast #bit (U64x2) quad1, cast #bit (U64x2) quad3)
        rows[][4] = cast #bit (U16x8) Swag.vecinterleavelo(cast #bit (U64x2) quad4, cast #bit (U64x2) quad6)
        rows[][5] = cast #bit (U16x8) Swag.vecinterleavehi(cast #bit (U64x2) quad4, cast #bit (U64x2) quad6)
        rows[][6] = cast #bit (U16x8) Swag.vecinterleavelo(cast #bit (U64x2) quad5, cast #bit (U64x2) quad7)
        rows[][7] = cast #bit (U16x8) Swag.vecinterleavehi(cast #bit (U64x2) quad5, cast #bit (U64x2) quad7)
    }
}

// The element-wise vector forms of the scalar functions of this namespace. [[Math.min]]
// and [[Math.max]] need no dedicated overloads: their generic forms accept the vector
// types directly.
#[Inline]
{
    // Returns the absolute value, per lane.
    func abs(x: Simd.S8x16)->Simd.S8x16 => Swag.abs(x)
    func abs(x: Simd.S16x8)->Simd.S16x8 => Swag.abs(x)
    func abs(x: Simd.S32x4)->Simd.S32x4 => Swag.abs(x)
    func abs(x: Simd.S64x2)->Simd.S64x2 => Swag.abs(x)

    // Returns the absolute value, per lane, by clearing the sign bit.
    //
    // A NaN keeps its payload and a negative zero becomes a positive one.
    func abs(x: Simd.F32x4)->Simd.F32x4 => Swag.abs(x)
    func abs(x: Simd.F64x2)->Simd.F64x2 => Swag.abs(x)

    // Returns the square root, per lane.
    func sqrt(x: Simd.F32x4)->Simd.F32x4 => Swag.sqrt(x)
    func sqrt(x: Simd.F64x2)->Simd.F64x2 => Swag.sqrt(x)

    // Multiplies two values and adds a third, per lane.
    func mulAdd(x, y, z: Simd.F32x4)->Simd.F32x4 => Swag.muladd(x, y, z)
    func mulAdd(x, y, z: Simd.F64x2)->Simd.F64x2 => Swag.muladd(x, y, z)

    // Rounds downward to an integer-valued number, per lane.
    func floor(x: Simd.F32x4)->Simd.F32x4 => Swag.floor(x)
    func floor(x: Simd.F64x2)->Simd.F64x2 => Swag.floor(x)

    // Rounds upward to an integer-valued number, per lane.
    func ceil(x: Simd.F32x4)->Simd.F32x4 => Swag.ceil(x)
    func ceil(x: Simd.F64x2)->Simd.F64x2 => Swag.ceil(x)

    // Removes the fractional part, per lane.
    func trunc(x: Simd.F32x4)->Simd.F32x4 => Swag.trunc(x)
    func trunc(x: Simd.F64x2)->Simd.F64x2 => Swag.trunc(x)

    // Rotates the bits of every lane left by `y`, taken modulo the lane width.
    func rol(x: Simd.U8x16, y: u8)->Simd.U8x16 => Swag.rol(x, y)
    func rol(x: Simd.U16x8, y: u8)->Simd.U16x8 => Swag.rol(x, y)
    func rol(x: Simd.U32x4, y: u8)->Simd.U32x4 => Swag.rol(x, y)
    func rol(x: Simd.U64x2, y: u8)->Simd.U64x2 => Swag.rol(x, y)

    // Rotates the bits of every lane right by `y`, taken modulo the lane width.
    func ror(x: Simd.U8x16, y: u8)->Simd.U8x16 => Swag.ror(x, y)
    func ror(x: Simd.U16x8, y: u8)->Simd.U16x8 => Swag.ror(x, y)
    func ror(x: Simd.U32x4, y: u8)->Simd.U32x4 => Swag.ror(x, y)
    func ror(x: Simd.U64x2, y: u8)->Simd.U64x2 => Swag.ror(x, y)

    // Returns the number of bits set to one, per lane.
    func countOnes(x: Simd.U8x16)->Simd.U8x16 => Swag.bitCountNz(x)
    func countOnes(x: Simd.U16x8)->Simd.U16x8 => Swag.bitCountNz(x)
    func countOnes(x: Simd.U32x4)->Simd.U32x4 => Swag.bitCountNz(x)
    func countOnes(x: Simd.U64x2)->Simd.U64x2 => Swag.bitCountNz(x)

    // Returns the number of zero bits above the highest set bit, per lane.
    //
    // An all-zero lane answers the lane width.
    func leadingZeros(x: Simd.U8x16)->Simd.U8x16 => Swag.bitCountLz(x)
    func leadingZeros(x: Simd.U16x8)->Simd.U16x8 => Swag.bitCountLz(x)
    func leadingZeros(x: Simd.U32x4)->Simd.U32x4 => Swag.bitCountLz(x)
    func leadingZeros(x: Simd.U64x2)->Simd.U64x2 => Swag.bitCountLz(x)

    // Returns the number of zero bits below the lowest set bit, per lane.
    //
    // An all-zero lane answers the lane width.
    func trailingZeros(x: Simd.U8x16)->Simd.U8x16 => Swag.bitCountTz(x)
    func trailingZeros(x: Simd.U16x8)->Simd.U16x8 => Swag.bitCountTz(x)
    func trailingZeros(x: Simd.U32x4)->Simd.U32x4 => Swag.bitCountTz(x)
    func trailingZeros(x: Simd.U64x2)->Simd.U64x2 => Swag.bitCountTz(x)

    // Reverses the bytes inside every lane.
    func byteswap(x: Simd.U16x8)->Simd.U16x8 => Swag.byteSwap(x)
    func byteswap(x: Simd.U32x4)->Simd.U32x4 => Swag.byteSwap(x)
    func byteswap(x: Simd.U64x2)->Simd.U64x2 => Swag.byteSwap(x)

    // Returns the magnitude of `x` carrying the sign of `y`, per lane.
    //
    // Only the sign bit moves, so a NaN keeps its payload and a zero takes the
    // sign it is given.
    func copysign(x, y: Simd.F32x4)->Simd.F32x4
    {
        const Magnitude = Swag.vecsplat(0x7FFF_FFFF'u32)
        const Sign      = Swag.vecsplat(0x8000_0000'u32)
        return cast #bit (Simd.F32x4) ((cast #bit (Simd.U32x4) x & Magnitude) | (cast #bit (Simd.U32x4) y & Sign))
    }

    func copysign(x, y: Simd.F64x2)->Simd.F64x2
    {
        const Magnitude = Swag.vecsplat(0x7FFF_FFFF_FFFF_FFFF'u64)
        const Sign      = Swag.vecsplat(0x8000_0000_0000_0000'u64)
        return cast #bit (Simd.F64x2) ((cast #bit (Simd.U64x2) x & Magnitude) | (cast #bit (Simd.U64x2) y & Sign))
    }

    // Returns the sign of every lane.
    //
    // A lane below zero answers -1 and a lane above it 1; zero and a NaN both
    // answer 0.
    func sign(x: Simd.F32x4)->Simd.F32x4
    {
        let zero     = Swag.vecsplat(0'f32)
        let one      = Swag.vecsplat(1'f32)
        let positive = Simd.select(x > zero, one, zero)
        let negative = Simd.select(x < zero, one, zero)
        return positive - negative
    }

    func sign(x: Simd.F64x2)->Simd.F64x2
    {
        let zero     = Swag.vecsplat(0'f64)
        let one      = Swag.vecsplat(1'f64)
        let positive = Simd.select(x > zero, one, zero)
        let negative = Simd.select(x < zero, one, zero)
        return positive - negative
    }

    // Clamps every lane between zero and one.
    func saturate(x: Simd.F32x4)->Simd.F32x4 => clamp(x, Swag.vecsplat(0'f32), Swag.vecsplat(1'f32))
    func saturate(x: Simd.F64x2)->Simd.F64x2 => clamp(x, Swag.vecsplat(0'f64), Swag.vecsplat(1'f64))

    // Interpolates linearly between `x` and `y`, per lane.
    func lerp(x, y, factor: Simd.F32x4)->Simd.F32x4 => x + factor * (y - x)
    func lerp(x, y, factor: Simd.F64x2)->Simd.F64x2 => x + factor * (y - x)
}
