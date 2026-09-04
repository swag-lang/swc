//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, and both the H.263 and MPEG quantisers.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns inverse quantisation and the inverse transform.
//
#global namespace Mpeg4
#global internal

using Core

// What a reconstructed coefficient may reach for eight-bit samples, clause 7.4.4.4.
const CoefficientFloor = -2048's32
const CoefficientCeil  = 2047's32

// The step the direct-current coefficient of an intra block is quantised with, Table 7-1.
//
// It is a formula rather than a table, and it differs between the two components.
func dcScaler(isLuma: bool, quant: u32)->u32
{
    if isLuma
    {
        if quant < 5 do
            return 8
        if quant < 9 do
            return 2 * quant
        if quant < 25 do
            return quant + 8
        return 2 * quant - 16
    }

    if quant < 5 do
        return 8
    if quant < 25 do
        return (quant + 13) / 2
    return quant - 6
}

// Turns the quantised levels of one block back into transform coefficients.
//
// The layer chooses between the two methods the format defines. The H.263 one scales every
// coefficient by the same step; the MPEG one weights each by its own position, and then repairs
// the parity of the block so that the transform cannot drift, clause 7.4.4.5.
//
// `hasDcLevel` is false when the direct current was read through its own code rather than as a
// coefficient, in which case it is already reconstructed and must not be scaled again.
func dequantise(block: *[64] s32, layer: const *Layer, quant: u32, intra, isLuma: bool)
{
    if !layer.quantType
    {
        // The H.263 method, clause 7.4.4.2.
        let odd = (quant & 1) != 0
        for index in 64'u64
        {
            if intra and !index do
                continue
            let level = block[][index]
            if !level
            {
                continue
            }

            let magnitude = cast(s32) quant * (2 * Math.abs(level) + 1) - (odd ? 0 : 1)
            block[][index] = Math.clamp(level < 0 ? -magnitude : magnitude, CoefficientFloor, CoefficientCeil)
        }

        return
    }

    // The MPEG method, clause 7.4.4.1: every position carries its own weight.
    let weights: const [..] u8 = intra ? layer.intraMatrix : layer.interMatrix
    var sum = 0's32
    for index in 64'u64
    {
        var value = 0's32
        if intra and !index
        {
            value = block[][0]
        }
        else
        {
            let level = block[][index]
            if level
            {
                let weight = cast(s32) weights[index]
                if intra do
                    value = (level * weight * cast(s32) quant * 2) / 16
                else do
                    value = ((2 * level + (level < 0 ? -1 : 1)) * weight * cast(s32) quant) / 16
            }
        }

        value          = Math.clamp(value, CoefficientFloor, CoefficientCeil)
        block[][index] = value
        sum            += value
    }

    // Clause 7.4.4.5 repairs the parity of the block. Every decoder in the field applies it to
    // predicted blocks only, and a stream encoded against one of those reconstructs wrongly if
    // an intra block is repaired as well.
    if !intra and !(sum & 1) do
        block[][63] ^= 1

    discard isLuma
}

// The cosines of the eight-point transform, `cos((2 * x + 1) * u * pi / 16) * (u ? 1 : 1/sqrt 2)`.
//
// The format states the transform as a formula, not as an integer network, and requires only that
// a decoder stay within the accuracy of clause A.1; this is the formula, evaluated once.
var g_Cosines:      [8, 8] f32
var g_CosinesReady: bool

func prepareCosines()
{
    if g_CosinesReady do
        return
    for u in 8'u64
    {
        let scale = u == 0 ? cast(f32) (1.0'f64 / Math.sqrt(2.0'f64)) : 1.0'f32
        for x in 8'u64 do
            g_Cosines[u, x] = scale * cast(f32) Math.cos(cast(f64) ((2 * x + 1) * u) * Math.ConstF64.Pi / 16.0'f64)
    }

    g_CosinesReady = true
}

// The inverse transform of one block, clause 7.4.5.
//
// Rows first, then columns, which is the separable form of the two-dimensional transform and what
// keeps it to a hundred and twenty-eight multiplications a sample rather than four thousand.
func inverseTransform(block: const *[64] s32, output: *[64] s16)
{
    prepareCosines()

    var rows: [64] f32
    for y in 8'u64
    {
        for x in 8'u64
        {
            var sum = 0'f32
            for u in 8'u64
            {
                let value = block[][y * 8 + u]
                if value do
                    sum += cast(f32) value * g_Cosines[u, x]
            }

            rows[y * 8 + x] = sum * 0.5
        }
    }

    for x in 8'u64
    {
        for y in 8'u64
        {
            var sum = 0'f32
            for v in 8'u64 do
                sum += rows[v * 8 + x] * g_Cosines[v, y]
            output[][y * 8 + x] = cast(s16) Math.clamp(cast(s32) Math.round(sum * 0.5), -512's32, 511's32)
        }
    }
}
