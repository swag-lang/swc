#global namespace Math
#global public

using Swag

// Packed 128-bit vector operations over the '#simd [N] T' types.
//
// The aliases name every legal 16-byte vector shape, lane type by lane count, and the
// functions give the packed hardware intrinsics their product spelling: memory transfers,
// saturating arithmetic, narrowing and widening, byte shuffles, and mask handling. Every
// operation maps to one instruction of the baseline instruction set.
//
// The rest of the vector vocabulary needs no function at all. Comparisons and the
// arithmetic, bitwise and shift operators are part of the language and compute per lane,
// and a scalar operand of an operator broadcasts over the other side's lanes. A `cast`
// reshapes 16 bytes — an array of the exact shape into a vector and back — while
// `cast #bit` reinterprets one vector shape as another. The element-wise forms of
// [[Math.min]], [[Math.max]], [[Math.abs]], [[Math.sqrt]], [[Math.mulAdd]], [[Math.floor]],
// [[Math.ceil]] and [[Math.trunc]] accept the vector types directly.
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

        // Adds the four lanes with wrapping arithmetic.
        func sum(value: S32x4)->s32 => @vecsum(value)

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
}
