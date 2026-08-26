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

        let coded    = cast(s32) MvdDelta[cast(u64) entry]
        var residual = 0's32
        if step != 1 and coded != 0 do
            residual = cast(s32) reader.read(bits)

        var value = coded
        if step != 1 and coded != 0
        {
            let magnitude = (Math.abs(coded) - 1) * step + residual + 1
            value = coded < 0 ? -magnitude : magnitude
        }

        if !component do
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
    let count = @countof(vectors)
    var sum: Vector
    for vector in vectors
    {
        sum.x += vector.x
        sum.y += vector.y
    }

    let table: const [..] u8 = count == 4 ? ChromaRoundFourBlocks
                               : (count == 3 ? ChromaRoundThreeBlocks
                                  : (count == 2 ? ChromaRoundTwoBlocks : ChromaRoundOneBlock))
    let span = 4's32 * cast(s32) count

    var result: retval
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

    return 2 * whole + cast(s32) table[cast(u64) residue]
}

// Copies one block out of a reference plane, interpolating where the vector points between
// samples, clause 7.6.2.
//
// The plane is padded far enough that a vector pointing outside the picture still reads inside
// the buffer, so no coordinate is tested here. Rounding control shifts every average by half a
// level, which is what keeps a long chain of predicted pictures from drifting.
func compensate(destination: [*] u8, destinationStride: u64, source: const [*] u8, sourceOrigin, sourceStride: u64, x, y: s32, vector: Vector, width, height, rounding: u32, planeWidth, planeHeight: u32)
{
    // A vector may point outside the picture. The padding holds what the edge holds, so reading
    // from the padding is what the format's unrestricted vectors mean; a vector that points
    // further than the padding reaches reads the same samples the padding would have repeated,
    // which is what clamping the position to it produces.
    let full  = 1 - cast(s32) rounding
    let limit = cast(s32) FramePadding - cast(s32) height - 2
    var fullX = x + (vector.x >> 1)
    var fullY = y + (vector.y >> 1)
    fullX = Math.clamp(fullX, -cast(s32) FramePadding, cast(s32) planeWidth + limit)
    fullY = Math.clamp(fullY, -cast(s32) FramePadding, cast(s32) planeHeight + limit)
    let halfX = (vector.x & 1) != 0
    let halfY = (vector.y & 1) != 0
    let at    = cast(u64) (cast(s64) sourceOrigin + cast(s64) fullY * cast(s64) sourceStride + cast(s64) fullX)

    if !halfX and !halfY
    {
        for row in cast(u64) height do
            Memory.copy(destination + row * destinationStride, source + at + row * sourceStride, cast(u64) width)
        return
    }

    if halfX and !halfY
    {
        for row in cast(u64) height
        {
            let line = at + row * sourceStride
            for column in cast(u64) width do
                destination[row * destinationStride + column] =
                    cast(u8) ((cast(s32) source[line + column] + cast(s32) source[line + column + 1] + full) >> 1)
        }

        return
    }

    if !halfX and halfY
    {
        for row in cast(u64) height
        {
            let line = at + row * sourceStride
            for column in cast(u64) width do
                destination[row * destinationStride + column] =
                    cast(u8) ((cast(s32) source[line + column] + cast(s32) source[line + sourceStride + column] + full) >> 1)
        }

        return
    }

    for row in cast(u64) height
    {
        let line = at + row * sourceStride
        for column in cast(u64) width
        {
            let a = cast(s32) source[line + column]
            let b = cast(s32) source[line + column + 1]
            let c = cast(s32) source[line + sourceStride + column]
            let d = cast(s32) source[line + sourceStride + column + 1]
            destination[row * destinationStride + column] = cast(u8) ((a + b + c + d + 2 - cast(s32) rounding) >> 2)
        }
    }
}

// Averages a second prediction into a block that already holds the first.
//
// A bidirectional block is the mean of what its two references say, rounded up, clause 7.6.7.
func blendInto(destination: [*] u8, destinationStride: u64, source: const [*] u8, sourceStride: u64, width, height: u32)
{
    for row in cast(u64) height
    {
        for column in cast(u64) width
        {
            let a = cast(u32) destination[row * destinationStride + column]
            let b = cast(u32) source[row * sourceStride + column]
            destination[row * destinationStride + column] = cast(u8) ((a + b + 1) >> 1)
        }
    }
}
