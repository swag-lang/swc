//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 Baseline, Main, and High-profile streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, non-4:2:0 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns inverse transforms and coefficient scaling.
//
#global namespace H264
#global internal

using Core

// Inverse transforms of section 8.5. Every routine adds its result to the prediction already
// sitting in the destination plane, clamping to the byte range.

// Branchless pixel-loop primitives. The backend lowers a ternary to a compare and branch,
// and a branch inside a pixel loop forces the register allocator to flush its live values to
// memory, so every clamp on the per-sample paths uses sign-bit arithmetic instead.

// Clamps one reconstructed sample.
#[Swag.Inline]
func clampPixel(value: s32)->u8
{
    let positive = value & ~(value >> 31)
    return cast(u8) ((positive | ((255 - positive) >> 31)) & 255)
}

// Returns `value` clamped to zero from below.
#[Swag.Inline]
func max0S32(value: s32)->s32 => value & ~(value >> 31)

// Returns the absolute value.
#[Swag.Inline]
func absS32(value: s32)->s32
{
    let sign = value >> 31
    return (value ^ sign) - sign
}

// Clamps `value` into `low`..`high`.
#[Swag.Inline]
func clampS32(value, low, high: s32)->s32
{
    let aboveLow  = value - low
    let floored   = low + (aboveLow & ~(aboveLow >> 31))
    let belowHigh = high - floored
    return high - (belowHigh & ~(belowHigh >> 31))
}

// Returns the smaller value.
#[Swag.Inline]
func minS32(a, b: s32)->s32
{
    let difference = a - b
    return b + (difference & (difference >> 31))
}

// Returns the larger value.
#[Swag.Inline]
func maxS32(a, b: s32)->s32
{
    let difference = a - b
    return a - (difference & (difference >> 31))
}

// The inverse 4x4 core transform of section 8.5.12.2 in 32-bit scalar arithmetic: the
// reference [[addIdct4x4]] is checked against.
//
// `block` is in natural raster order, exactly as [[Decoder.dequant4x4]] builds it. The spec's
// pass order follows: rows first, then each intermediate column lands in one destination
// column, with the final rounding bias riding on the DC coefficient.
func addIdct4x4Scalar(destination: [*] u8, stride: u64, block: [*] s16)
{
    var work: [16] s32 = undefined
    for index in 16'u64 do
        work[index] = cast(s32) block[index]
    work[0] += 32

    for row in 4'u64
    {
        let base = row * 4
        let z0   = work[base] + work[base + 2]
        let z1   = work[base] - work[base + 2]
        let z2   = (work[base + 1] >> 1) - work[base + 3]
        let z3   = work[base + 1] + (work[base + 3] >> 1)
        work[base]     = z0 + z3
        work[base + 1] = z1 + z2
        work[base + 2] = z1 - z2
        work[base + 3] = z0 - z3
    }

    for column in 4'u64
    {
        let z0 = work[column] + work[column + 8]
        let z1 = work[column] - work[column + 8]
        let z2 = (work[column + 4] >> 1) - work[column + 12]
        let z3 = work[column + 4] + (work[column + 12] >> 1)
        destination[column]              = clampPixel(cast(s32) destination[column] + ((z0 + z3) >> 6))
        destination[stride + column]     = clampPixel(cast(s32) destination[stride + column] + ((z1 + z2) >> 6))
        destination[stride * 2 + column] = clampPixel(cast(s32) destination[stride * 2 + column] + ((z1 - z2) >> 6))
        destination[stride * 3 + column] = clampPixel(cast(s32) destination[stride * 3 + column] + ((z0 - z3) >> 6))
    }
}

// Adds the inverse 4x4 core transform of `block` to the destination, section 8.5.12.2, in
// 16-bit lanes. The row pass runs on the four columns held two per vector, a transpose turns
// its result back into rows, the column pass runs the same butterfly on those, and the
// prediction is added two rows per vector. A conforming stream keeps every intermediate of
// this transform in the 16-bit range (8.5.12), so the lanes never wrap where the 32-bit
// scalar form would not, and the result is exactly [[addIdct4x4Scalar]].
func addIdct4x4(destination: [*] u8, stride: u64, block: [*] s16)
{
    const Bias       = cast(Simd.S16x8) [32's16, 0, 0, 0, 0, 0, 0, 0]
    const SwapHalves = cast(Simd.U8x16) [8'u8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7]

    // Rows 0,1 and rows 2,3, the rounding bias riding on the DC coefficient; then the
    // columns, two per vector: `x` holds columns 0 and 1, `y` columns 2 and 3.
    let rows01 = cast #bit(Simd.U16x8) (Simd.load(block) + Bias)
    let rows23 = cast #bit(Simd.U16x8) Simd.load(block + 8)
    let even   = Simd.interleaveLow(rows01, rows23)
    let odd    = Simd.interleaveHigh(rows01, rows23)
    let x      = cast #bit(Simd.S16x8) Simd.interleaveLow(even, odd)
    let y      = cast #bit(Simd.S16x8) Simd.interleaveHigh(even, odd)

    // The butterfly on a column pair leaves z0, z1 in the low halves and z2, z3 in the high
    // ones; regrouping them by 64-bit halves gives the four outputs as [col0 | col1] and
    // [col3 | col2].
    let z01   = cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U64x2) (x + y), cast #bit(Simd.U64x2) (x - y))
    let z32   = cast #bit(Simd.S16x8) Simd.interleaveHigh(cast #bit(Simd.U64x2) (x + (y >> 1)), cast #bit(Simd.U64x2) ((x >> 1) - y))
    let col01 = cast #bit(Simd.U16x8) (z01 + z32)
    let col23 = cast #bit(Simd.U16x8) Simd.shuffle(cast #bit(Simd.U8x16) (z01 - z32), SwapHalves)

    // Back to rows for the same butterfly down the columns.
    let even2     = Simd.interleaveLow(col01, col23)
    let odd2      = Simd.interleaveHigh(col01, col23)
    let rx        = cast #bit(Simd.S16x8) Simd.interleaveLow(even2, odd2)
    let ry        = cast #bit(Simd.S16x8) Simd.interleaveHigh(even2, odd2)
    let w01       = cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U64x2) (rx + ry), cast #bit(Simd.U64x2) (rx - ry))
    let w32       = cast #bit(Simd.S16x8) Simd.interleaveHigh(cast #bit(Simd.U64x2) (rx + (ry >> 1)), cast #bit(Simd.U64x2) ((rx >> 1) - ry))
    let rows01Out = (w01 + w32) >> 6
    let rows32Out = (w01 - w32) >> 6

    // Prediction rows 0,1 and 3,2, in the order the outputs come out, added and clamped.
    let pred01 = cast #bit(Simd.S16x8) Simd.widenLow(cast #bit(Simd.U8x16) Simd.interleaveLow(cast #bit(Simd.U32x4) Simd.load(destination), cast #bit(Simd.U32x4) Simd.load(destination + stride)))
    let pred32 = cast #bit(Simd.S16x8) Simd.widenLow(cast #bit(Simd.U8x16) Simd.interleaveLow(cast #bit(Simd.U32x4) Simd.load(destination + 3 * stride), cast #bit(Simd.U32x4) Simd.load(destination + 2 * stride)))
    let sum01  = pred01 + rows01Out
    let sum32  = pred32 + rows32Out
    let out01  = cast #bit(Simd.U32x4) Simd.packUnsigned(sum01, sum01)
    let out32  = cast #bit(Simd.U32x4) Simd.packUnsigned(sum32, sum32)
    (cast([*] u32) destination)[0]                = out01[0]
    (cast([*] u32) (destination + stride))[0]     = out01[1]
    (cast([*] u32) (destination + 3 * stride))[0] = out32[0]
    (cast([*] u32) (destination + 2 * stride))[0] = out32[1]
}

// Adds a flat DC-only 4x4 block to the destination: the rounded value broadcasts over eight
// lanes and two prediction rows ride in one vector. A value beyond one byte either way
// clamps every sample the same, so it is held within that range before it narrows to the
// lanes.
func addDc4x4(destination: [*] u8, stride: u64, dc: s32)
{
    let value  = Simd.splat(cast(s16) Math.clamp((dc + 32) >> 6, -256, 256))
    let pred01 = cast #bit(Simd.S16x8) Simd.widenLow(cast #bit(Simd.U8x16) Simd.interleaveLow(cast #bit(Simd.U32x4) Simd.load(destination), cast #bit(Simd.U32x4) Simd.load(destination + stride)))
    let pred23 = cast #bit(Simd.S16x8) Simd.widenLow(cast #bit(Simd.U8x16) Simd.interleaveLow(cast #bit(Simd.U32x4) Simd.load(destination + 2 * stride), cast #bit(Simd.U32x4) Simd.load(destination + 3 * stride)))
    let sum01  = pred01 + value
    let sum23  = pred23 + value
    let out01  = cast #bit(Simd.U32x4) Simd.packUnsigned(sum01, sum01)
    let out23  = cast #bit(Simd.U32x4) Simd.packUnsigned(sum23, sum23)
    (cast([*] u32) destination)[0]                = out01[0]
    (cast([*] u32) (destination + stride))[0]     = out01[1]
    (cast([*] u32) (destination + 2 * stride))[0] = out23[0]
    (cast([*] u32) (destination + 3 * stride))[0] = out23[1]
}

// The flat DC-only add in scalar form: the reference [[addDc4x4]] is checked against.
func addDc4x4Scalar(destination: [*] u8, stride: u64, dc: s32)
{
    let value = (dc + 32) >> 6
    for row in 4'u64
    {
        for column in 4'u64 do
            destination[row * stride + column] = clampPixel(cast(s32) destination[row * stride + column] + value)
    }
}

// Inverse 4x4 Hadamard transform of the intra-16x16 luma DC coefficients, section 8.5.10.
//
// `block` holds the raw decoded coefficients in raster order and receives the transformed
// values, before their own dequantization.
func hadamard4x4Scalar(block: [*] s16)
{
    var work: [16] s32 = undefined
    for row in 4'u64
    {
        let c0 = cast(s32) block[row * 4 + 0]
        let c1 = cast(s32) block[row * 4 + 1]
        let c2 = cast(s32) block[row * 4 + 2]
        let c3 = cast(s32) block[row * 4 + 3]
        let e0 = c0 + c2
        let e1 = c0 - c2
        let e2 = c1 - c3
        let e3 = c1 + c3
        work[row * 4 + 0] = e0 + e3
        work[row * 4 + 1] = e1 + e2
        work[row * 4 + 2] = e1 - e2
        work[row * 4 + 3] = e0 - e3
    }

    for column in 4'u64
    {
        let c0 = work[column]
        let c1 = work[4 + column]
        let c2 = work[8 + column]
        let c3 = work[12 + column]
        let e0 = c0 + c2
        let e1 = c0 - c2
        let e2 = c1 - c3
        let e3 = c1 + c3
        block[column]      = cast(s16) clampS32(e0 + e3, -32768, 32767)
        block[4 + column]  = cast(s16) clampS32(e1 + e2, -32768, 32767)
        block[8 + column]  = cast(s16) clampS32(e1 - e2, -32768, 32767)
        block[12 + column] = cast(s16) clampS32(e0 - e3, -32768, 32767)
    }
}

// Applies one four-point Hadamard pass to four vectors. Each lane is an independent
// transform, and the four outputs replace the inputs.
#[Swag.Mixin]
private func hadamard4Lanes()
{
    {
        let e0 = r0 + r2
        let e1 = r0 - r2
        let e2 = r1 - r3
        let e3 = r1 + r3
        r0 = e0 + e3
        r1 = e1 + e2
        r2 = e1 - e2
        r3 = e0 - e3
    }
}

// Transposes the caller's four vectors of four 32-bit lanes without leaving registers.
#[Swag.Mixin]
private func transpose4x4Lanes()
{
    {
        let a0 = Simd.interleaveLow(cast #bit(Simd.U32x4) r0, cast #bit(Simd.U32x4) r1)
        let a1 = Simd.interleaveHigh(cast #bit(Simd.U32x4) r0, cast #bit(Simd.U32x4) r1)
        let a2 = Simd.interleaveLow(cast #bit(Simd.U32x4) r2, cast #bit(Simd.U32x4) r3)
        let a3 = Simd.interleaveHigh(cast #bit(Simd.U32x4) r2, cast #bit(Simd.U32x4) r3)
        r0 = cast #bit(Simd.S32x4) Simd.interleaveLow(cast #bit(Simd.U64x2) a0, cast #bit(Simd.U64x2) a2)
        r1 = cast #bit(Simd.S32x4) Simd.interleaveHigh(cast #bit(Simd.U64x2) a0, cast #bit(Simd.U64x2) a2)
        r2 = cast #bit(Simd.S32x4) Simd.interleaveLow(cast #bit(Simd.U64x2) a1, cast #bit(Simd.U64x2) a3)
        r3 = cast #bit(Simd.S32x4) Simd.interleaveHigh(cast #bit(Simd.U64x2) a1, cast #bit(Simd.U64x2) a3)
    }
}

// Inverse 4x4 Hadamard transform in 32-bit lanes. The two separable passes remain in
// registers, and the final signed pack performs the same clamp as [[hadamard4x4Scalar]].
func hadamard4x4(block: [*] s16)
{
    let rows01 = Simd.load(block)
    let rows23 = Simd.load(block + 8)
    var r0     = Simd.widenLow(rows01)
    var r1     = Simd.widenHigh(rows01)
    var r2     = Simd.widenLow(rows23)
    var r3     = Simd.widenHigh(rows23)

    hadamard4Lanes()
    transpose4x4Lanes()
    hadamard4Lanes()
    transpose4x4Lanes()

    Simd.store(block, Simd.packSigned(r0, r1))
    Simd.store(block + 8, Simd.packSigned(r2, r3))
}

// Inverse 2x2 Hadamard transform of the chroma DC coefficients, section 8.5.11.
func hadamard2x2(block: [*] s16)
{
    let c0 = cast(s32) block[0]
    let c1 = cast(s32) block[1]
    let c2 = cast(s32) block[2]
    let c3 = cast(s32) block[3]
    block[0] = cast(s16) (c0 + c1 + c2 + c3)
    block[1] = cast(s16) (c0 - c1 + c2 - c3)
    block[2] = cast(s16) (c0 + c1 - c2 - c3)
    block[3] = cast(s16) (c0 - c1 - c2 + c3)
}

// The inverse 8x8 transform of section 8.5.13.1 in 32-bit scalar arithmetic: the reference
// [[addIdct8x8]] is checked against.
//
// Structured exactly like [[addIdct4x4Scalar]]: natural raster input, rows first, then each
// intermediate column lands in one destination column.
func addIdct8x8Scalar(destination: [*] u8, stride: u64, block: [*] s16)
{
    var work: [64] s32 = undefined
    for index in 64'u64 do
        work[index] = cast(s32) block[index]
    work[0] += 32

    for row in 8'u64
    {
        let base = row * 8
        let c0   = work[base + 0]
        let c1   = work[base + 1]
        let c2   = work[base + 2]
        let c3   = work[base + 3]
        let c4   = work[base + 4]
        let c5   = work[base + 5]
        let c6   = work[base + 6]
        let c7   = work[base + 7]

        let a0 = c0 + c4
        let a2 = c0 - c4
        let a4 = (c2 >> 1) - c6
        let a6 = (c6 >> 1) + c2
        let b0 = a0 + a6
        let b2 = a2 + a4
        let b4 = a2 - a4
        let b6 = a0 - a6

        let a1 = -c3 + c5 - c7 - (c7 >> 1)
        let a3 = c1 + c7 - c3 - (c3 >> 1)
        let a5 = -c1 + c7 + c5 + (c5 >> 1)
        let a7 = c3 + c5 + c1 + (c1 >> 1)
        let b1 = (a7 >> 2) + a1
        let b3 = a3 + (a5 >> 2)
        let b5 = (a3 >> 2) - a5
        let b7 = a7 - (a1 >> 2)

        work[base + 0] = b0 + b7
        work[base + 7] = b0 - b7
        work[base + 1] = b2 + b5
        work[base + 6] = b2 - b5
        work[base + 2] = b4 + b3
        work[base + 5] = b4 - b3
        work[base + 3] = b6 + b1
        work[base + 4] = b6 - b1
    }

    for column in 8'u64
    {
        let c0 = work[column]
        let c1 = work[column + 8]
        let c2 = work[column + 16]
        let c3 = work[column + 24]
        let c4 = work[column + 32]
        let c5 = work[column + 40]
        let c6 = work[column + 48]
        let c7 = work[column + 56]

        let a0 = c0 + c4
        let a2 = c0 - c4
        let a4 = (c2 >> 1) - c6
        let a6 = (c6 >> 1) + c2
        let b0 = a0 + a6
        let b2 = a2 + a4
        let b4 = a2 - a4
        let b6 = a0 - a6

        let a1 = -c3 + c5 - c7 - (c7 >> 1)
        let a3 = c1 + c7 - c3 - (c3 >> 1)
        let a5 = -c1 + c7 + c5 + (c5 >> 1)
        let a7 = c3 + c5 + c1 + (c1 >> 1)
        let b1 = (a7 >> 2) + a1
        let b3 = a3 + (a5 >> 2)
        let b5 = (a3 >> 2) - a5
        let b7 = a7 - (a1 >> 2)

        destination[column]              = clampPixel(cast(s32) destination[column] + ((b0 + b7) >> 6))
        destination[stride + column]     = clampPixel(cast(s32) destination[stride + column] + ((b2 + b5) >> 6))
        destination[stride * 2 + column] = clampPixel(cast(s32) destination[stride * 2 + column] + ((b4 + b3) >> 6))
        destination[stride * 3 + column] = clampPixel(cast(s32) destination[stride * 3 + column] + ((b6 + b1) >> 6))
        destination[stride * 4 + column] = clampPixel(cast(s32) destination[stride * 4 + column] + ((b6 - b1) >> 6))
        destination[stride * 5 + column] = clampPixel(cast(s32) destination[stride * 5 + column] + ((b4 - b3) >> 6))
        destination[stride * 6 + column] = clampPixel(cast(s32) destination[stride * 6 + column] + ((b2 - b5) >> 6))
        destination[stride * 7 + column] = clampPixel(cast(s32) destination[stride * 7 + column] + ((b0 - b7) >> 6))
    }
}

// The eight-point inverse transform of section 8.5.13.1 across the caller's lane vectors
// `r0`..`r7` — the columns during the row pass, the rows during the column pass — every lane
// one independent transform, the eight outputs written back into the same eight vectors. A
// mixin rather than a function so the vectors stay in registers: a callee taking their
// addresses would pin them to the stack.
#[Swag.Mixin]
private func idct8Lanes()
{
    {
        let a0 = r0 + r4
        let a2 = r0 - r4
        let a4 = (r2 >> 1) - r6
        let a6 = (r6 >> 1) + r2
        let b0 = a0 + a6
        let b2 = a2 + a4
        let b4 = a2 - a4
        let b6 = a0 - a6

        let a1 = r5 - r3 - r7 - (r7 >> 1)
        let a3 = r1 + r7 - r3 - (r3 >> 1)
        let a5 = r7 - r1 + r5 + (r5 >> 1)
        let a7 = r3 + r5 + r1 + (r1 >> 1)
        let b1 = (a7 >> 2) + a1
        let b3 = a3 + (a5 >> 2)
        let b5 = (a3 >> 2) - a5
        let b7 = a7 - (a1 >> 2)

        r0 = b0 + b7
        r7 = b0 - b7
        r1 = b2 + b5
        r6 = b2 - b5
        r2 = b4 + b3
        r5 = b4 - b3
        r3 = b6 + b1
        r4 = b6 - b1
    }
}

// Transposes the caller's eight vectors `r0`..`r7` of eight 16-bit lanes, in registers, so
// the lane that walked the rows now walks the columns and back.
#[Swag.Mixin]
private func transpose8x8Lanes()
{
    {
        let a0 = Simd.interleaveLow(cast #bit(Simd.U16x8) r0, cast #bit(Simd.U16x8) r1)
        let a1 = Simd.interleaveHigh(cast #bit(Simd.U16x8) r0, cast #bit(Simd.U16x8) r1)
        let a2 = Simd.interleaveLow(cast #bit(Simd.U16x8) r2, cast #bit(Simd.U16x8) r3)
        let a3 = Simd.interleaveHigh(cast #bit(Simd.U16x8) r2, cast #bit(Simd.U16x8) r3)
        let a4 = Simd.interleaveLow(cast #bit(Simd.U16x8) r4, cast #bit(Simd.U16x8) r5)
        let a5 = Simd.interleaveHigh(cast #bit(Simd.U16x8) r4, cast #bit(Simd.U16x8) r5)
        let a6 = Simd.interleaveLow(cast #bit(Simd.U16x8) r6, cast #bit(Simd.U16x8) r7)
        let a7 = Simd.interleaveHigh(cast #bit(Simd.U16x8) r6, cast #bit(Simd.U16x8) r7)

        let b0 = Simd.interleaveLow(cast #bit(Simd.U32x4) a0, cast #bit(Simd.U32x4) a2)
        let b1 = Simd.interleaveHigh(cast #bit(Simd.U32x4) a0, cast #bit(Simd.U32x4) a2)
        let b2 = Simd.interleaveLow(cast #bit(Simd.U32x4) a1, cast #bit(Simd.U32x4) a3)
        let b3 = Simd.interleaveHigh(cast #bit(Simd.U32x4) a1, cast #bit(Simd.U32x4) a3)
        let b4 = Simd.interleaveLow(cast #bit(Simd.U32x4) a4, cast #bit(Simd.U32x4) a6)
        let b5 = Simd.interleaveHigh(cast #bit(Simd.U32x4) a4, cast #bit(Simd.U32x4) a6)
        let b6 = Simd.interleaveLow(cast #bit(Simd.U32x4) a5, cast #bit(Simd.U32x4) a7)
        let b7 = Simd.interleaveHigh(cast #bit(Simd.U32x4) a5, cast #bit(Simd.U32x4) a7)

        r0 = cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U64x2) b0, cast #bit(Simd.U64x2) b4)
        r1 = cast #bit(Simd.S16x8) Simd.interleaveHigh(cast #bit(Simd.U64x2) b0, cast #bit(Simd.U64x2) b4)
        r2 = cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U64x2) b1, cast #bit(Simd.U64x2) b5)
        r3 = cast #bit(Simd.S16x8) Simd.interleaveHigh(cast #bit(Simd.U64x2) b1, cast #bit(Simd.U64x2) b5)
        r4 = cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U64x2) b2, cast #bit(Simd.U64x2) b6)
        r5 = cast #bit(Simd.S16x8) Simd.interleaveHigh(cast #bit(Simd.U64x2) b2, cast #bit(Simd.U64x2) b6)
        r6 = cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U64x2) b3, cast #bit(Simd.U64x2) b7)
        r7 = cast #bit(Simd.S16x8) Simd.interleaveHigh(cast #bit(Simd.U64x2) b3, cast #bit(Simd.U64x2) b7)
    }
}

// Adds one transformed row to its prediction row and stores the eight clamped samples.
#[Swag.Inline]
private func addRow8(destination: [*] u8, row: Simd.S16x8)
{
    let pred = cast #bit(Simd.S16x8) Simd.widenLow(Simd.load(destination))
    let sum  = pred + (row >> 6)
    Simd.storeLow8(destination, Simd.packUnsigned(sum, sum))
}

// Adds the inverse 8x8 transform of `block` to the destination, section 8.5.13.1, in 16-bit
// lanes: rows first, as the spec orders it, by transposing the block so one vector holds one
// column and the lanes walk the rows, then back to rows for the column pass. A conforming
// stream keeps every intermediate in the 16-bit range, so the lanes never wrap where the
// 32-bit scalar form would not, and the result is exactly [[addIdct8x8Scalar]].
func addIdct8x8(destination: [*] u8, stride: u64, block: [*] s16)
{
    const Bias = cast(Simd.S16x8) [32's16, 0, 0, 0, 0, 0, 0, 0]
    var r0 = Simd.load(block) + Bias
    var r1 = Simd.load(block + 8)
    var r2 = Simd.load(block + 16)
    var r3 = Simd.load(block + 24)
    var r4 = Simd.load(block + 32)
    var r5 = Simd.load(block + 40)
    var r6 = Simd.load(block + 48)
    var r7 = Simd.load(block + 56)

    transpose8x8Lanes()
    idct8Lanes()
    transpose8x8Lanes()
    idct8Lanes()

    addRow8(destination, r0)
    addRow8(destination + stride, r1)
    addRow8(destination + 2 * stride, r2)
    addRow8(destination + 3 * stride, r3)
    addRow8(destination + 4 * stride, r4)
    addRow8(destination + 5 * stride, r5)
    addRow8(destination + 6 * stride, r6)
    addRow8(destination + 7 * stride, r7)
}
