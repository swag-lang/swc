//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, and both the H.263 and MPEG quantisers.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns motion vectors: decoding them, predicting them, and compensating with them.
//
#global namespace Mpeg4
#global internal

using Core, Core.Errors

// One motion vector, in half samples.
struct Vector
{
    x: s32
    y: s32
}

// The middle of three values, which is what the format predicts a vector with.
func median(a, b, c: s32)->s32 => Math.max(Math.min(a, b), Math.min(Math.max(a, b), c))

// Reads one motion vector difference, clause 7.6.3.
//
// The code names a value on a coarse grid, and a residual of `fcode - 1` bits says where inside
// that step the vector sits. A code of zero carries no residual whatever the step.
func readVectorDelta(reader: *BitReader, fcode: u32, result: *Vector)->bool
{
    let step = 1's32 << (fcode - 1)
    let bits = fcode - 1

    for component in 2'u32
    {
        let entry = reader.decode(MvdTree)
        if entry < 0 do
            return false

        let coded    = cast(s32, MvdDelta[cast(u64, entry)])
        var residual = 0's32
        if step != 1 and coded != 0 do
            residual = cast(s32, reader.read(bits))

        var value = coded
        if step != 1 and coded != 0
        {
            let magnitude = (Math.abs(coded) - 1) * step + residual + 1
            value = coded < 0 ? -magnitude : magnitude
        }

        if not component do
            result.x = value
        else do
            result.y = value
    }

    return true
}

// Folds a predicted vector back into the range the code allows, clause 7.6.3.
func wrapVector(value: s32, fcode: u32)->s32
{
    let step  = 1's32 << (fcode - 1)
    let low   = -32 * step
    let high  = 32 * step - 1
    let range = 64 * step

    var result = value
    if result < low do
        result += range
    if result > high do
        result -= range
    return result
}

// Turns the luminance vectors of one macroblock into the vector its chrominance uses,
// clause 7.6.5.
//
// The sum is divided by twice the number of contributing blocks, and what the division leaves
// over rounds through the table for that count.
func chromaVector(vectors: const [..] Vector)->Vector
{
    let count = vectors.count
    var sum: Vector
    for vector in vectors
    {
        sum.x += vector.x
        sum.y += vector.y
    }

    let table: const [..] u8 = count == 4 ? ChromaRoundFourBlocks
                               : (count == 3 ? ChromaRoundThreeBlocks
                                  : (count == 2 ? ChromaRoundTwoBlocks : ChromaRoundOneBlock))
    let span = 4's32 * cast(s32, count)

    var result: #returntype
    result.x = reduceChroma(sum.x, span, table)
    result.y = reduceChroma(sum.y, span, table)
    return result
}

// One component of the chrominance vector: whole chrominance samples, plus the rounded residue.
//
// The residue has to stay positive for a vector pointing up or left, so the division floors
// rather than truncating.
private func reduceChroma(sum, span: s32, table: const [..] u8)->s32
{
    var whole   = sum / span
    var residue = sum % span
    if residue < 0
    {
        whole   -= 1
        residue += span
    }

    return 2 * whole + cast(s32, table[cast(u64, residue)])
}

// A prediction covers one 8x8 block of the padded reference plane.
private const BlockSize = 8'u64

#[Swag.Inline]
func loadPixels(source: const [*] u8)->Math.Simd.U8x16
{
    return cast #bit(Math.Simd.U8x16, Math.Simd.splat(cast(const [*] u64, source)[0]))
}

#[Swag.Inline]
private func interpolatePair(a, b: Math.Simd.U8x16, rounding: u32)->Math.Simd.U8x16
{
    let average = Math.Simd.average(a, b)

    // The hardware rounds up. Rounding control removes that increment from odd sums.
    return rounding ? average - ((a ^ b) & Math.Simd.splat(1'u8)) : average
}

// Copies one block out of a reference plane, interpolating where the vector points between
// samples, clause 7.6.2.
//
// Rounding control shifts every average by half a level, which is what keeps a long chain of
// predicted pictures from drifting.
func compensate(destination: [*] u8, destinationStride: u64, source: const [*] u8, sourceOrigin, sourceStride: u64, x, y: s32, vector: Vector, rounding, planeWidth, planeHeight: u32)
{
    // A vector may point outside the picture. Clamp to where the replicated edge still
    // supplies a whole block and the extra sample needed for half-sample interpolation.
    let limit = cast(s32, FramePadding) - cast(s32, BlockSize) - 2
    let fullX = Math.clamp(x + (vector.x >> 1), -cast(s32, FramePadding), cast(s32, planeWidth) + limit)
    let fullY = Math.clamp(y + (vector.y >> 1), -cast(s32, FramePadding), cast(s32, planeHeight) + limit)
    let halfX = (vector.x & 1) != 0
    let halfY = (vector.y & 1) != 0
    let at    = cast(u64, (cast(s64, sourceOrigin) + cast(s64, fullY) * cast(s64, sourceStride) + cast(s64, fullX)))
    let first = source + at

    if not halfX and not halfY
    {
        for row in BlockSize do
            cast([*] u64, destination + row * destinationStride)[0] = cast(const [*] u64, first + row * sourceStride)[0]
        return
    }

    if halfX != halfY
    {
        let step = halfX ? 1'u64 : sourceStride
        for row in BlockSize
        {
            let line   = first + row * sourceStride
            let pixels = interpolatePair(loadPixels(line), loadPixels(line + step), rounding)
            Math.Simd.storeLow8(destination + row * destinationStride, pixels)
        }

        return
    }

    let bias = Math.Simd.splat(cast(u16, 2 - rounding))
    for row in BlockSize
    {
        let top     = first + row * sourceStride
        let bottom  = top + sourceStride
        let a       = Math.Simd.widenLow(loadPixels(top))
        let b       = Math.Simd.widenLow(loadPixels(top + 1))
        let c       = Math.Simd.widenLow(loadPixels(bottom))
        let d       = Math.Simd.widenLow(loadPixels(bottom + 1))
        let samples = cast #bit(Math.Simd.S16x8, ((a + b + c + d + bias) >> 2))
        Math.Simd.storeLow8(destination + row * destinationStride, Math.Simd.packUnsigned(samples, samples))
    }
}

// Averages a second prediction into a block that already holds the first.
//
// A bidirectional block is the mean of what its two references say, rounded up, clause 7.6.7.
func blendInto(destination: [*] u8, destinationStride: u64, source: const [*] u8, sourceStride: u64)
{
    for row in BlockSize
    {
        let into = destination + row * destinationStride
        let from = source + row * sourceStride
        Math.Simd.storeLow8(into, Math.Simd.average(loadPixels(into), loadPixels(from)))
    }
}
