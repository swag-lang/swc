#global namespace H264
#global internal

using Core

// Inverse transforms of section 8.5. Every routine adds its result to the prediction already
// sitting in the destination plane, clamping to the byte range.

// Clamps one reconstructed sample.
#[Swag.Inline]
func clampPixel(value: s32)->u8 => cast(u8) Math.clamp(value, 0, 255)

// Adds the inverse 4x4 core transform of `block` to the destination, section 8.5.12.2.
//
// `block` is in natural raster order, exactly as [[Decoder.dequant4x4]] builds it. The spec's
// pass order follows: rows first, then each intermediate column lands in one destination
// column, with the final rounding bias riding on the DC coefficient.
func addIdct4x4(destination: [*] u8, stride: u64, block: [*] s16)
{
    var work: [16] s32 = undefined
    for index in 16'u64 do
        work[index] = cast(s32) block[index]
    work[0] += 32

    for row in 4'u64
    {
        let base = row * 4
        let z0 = work[base] + work[base + 2]
        let z1 = work[base] - work[base + 2]
        let z2 = (work[base + 1] >> 1) - work[base + 3]
        let z3 = work[base + 1] + (work[base + 3] >> 1)
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

// Adds a flat DC-only 4x4 block to the destination.
func addDc4x4(destination: [*] u8, stride: u64, dc: s32)
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
func hadamard4x4(block: [*] s16)
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
        block[column]      = cast(s16) Math.clamp(e0 + e3, -32768, 32767)
        block[4 + column]  = cast(s16) Math.clamp(e1 + e2, -32768, 32767)
        block[8 + column]  = cast(s16) Math.clamp(e1 - e2, -32768, 32767)
        block[12 + column] = cast(s16) Math.clamp(e0 - e3, -32768, 32767)
    }
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

// Adds the inverse 8x8 transform of `block` to the destination, section 8.5.13.1.
//
// Structured exactly like [[addIdct4x4]]: natural raster input, rows first, then each
// intermediate column lands in one destination column.
func addIdct8x8(destination: [*] u8, stride: u64, block: [*] s16)
{
    var work: [64] s32 = undefined
    for index in 64'u64 do
        work[index] = cast(s32) block[index]
    work[0] += 32

    for row in 8'u64
    {
        let base = row * 8
        let c0 = work[base + 0]
        let c1 = work[base + 1]
        let c2 = work[base + 2]
        let c3 = work[base + 3]
        let c4 = work[base + 4]
        let c5 = work[base + 5]
        let c6 = work[base + 6]
        let c7 = work[base + 7]

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
