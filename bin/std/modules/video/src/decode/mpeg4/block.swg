//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, and both the H.263 and MPEG quantisers.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns inverse quantisation and the inverse transform.
//
#global namespace Mpeg4
#global internal

using Core, Core.Math

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
// An `intra` block keeps its direct-current coefficient as it is: that value was read through its
// own code and already reconstructed, so it must not be scaled again.
func dequantise(block: *[64] s32, layer: const *Layer, quant: u32, intra: bool)
{
    if not layer.quantType
    {
        // The H.263 method, clause 7.4.4.2.
        let odd = (quant & 1) != 0
        for index in 64'u64
        {
            if intra and not index do
                continue
            let level = block[][index]
            if not level
            {
                continue
            }

            let magnitude = cast(s32, quant) * (2 * Math.abs(level) + 1) - (odd ? 0 : 1)
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
        if intra and not index
        {
            value = block[][0]
        }
        else
        {
            let level = block[][index]
            if level
            {
                let weight = cast(s32, weights[index])
                if intra do
                    value = (level * weight * cast(s32, quant) * 2) / 16
                else do
                    value = ((2 * level + (level < 0 ? -1 : 1)) * weight * cast(s32, quant)) / 16
            }
        }

        value = Math.clamp(value, CoefficientFloor, CoefficientCeil)
        block[][index] = value
        sum   += value
    }

    // Clause 7.4.4.5 repairs the parity of the block. Every decoder in the field applies it to
    // predicted blocks only, and a stream encoded against one of those reconstructs wrongly if
    // an intra block is repaired as well.
    if not intra and not (sum & 1) do
        block[][63] ^= 1
}

// The cosines of the eight-point transform, `cos((2 * x + 1) * u * pi / 16) * (u ? 1 : 1/sqrt 2)`.
//
// Build the coefficients once at compile time, shared by every decoder.
private func buildCosines()->[8, 8] f32
{
    var cosines: [8, 8] f32
    for u in 8'u64
    {
        let scale = u == 0 ? cast(f32, (1.0'f64 / Math.sqrt(2.0'f64))) : 1.0'f32
        for x in 8'u64 do
            cosines[u, x] = scale * cast(f32, Math.cos(cast(f64, ((2 * x + 1) * u)) * Math.ConstF64.Pi / 16.0'f64))
    }

    return cosines
}

private var g_Cosines: [8, 8] f32 = #run buildCosines()

// A block with only DC runs the DC lane of both transform passes, with their original rounding.
func dcSample(coefficient: s32)->u8
{
    let basis = g_Cosines[0, 0]
    let row   = cast(f32, coefficient) * basis * 0.5'f32
    let value = cast(s32, Math.round(row * basis * 0.5'f32))
    return cast(u8, Math.clamp(value, 0's32, 255's32))
}

// The inverse transform of one block, clause 7.4.5.
//
// Each SIMD lane evaluates an independent output column, keeping the coefficient sum in
// ascending frequency order in both passes.
func inverseTransform(block: const *[64] s32, output: *[64] s16)
{
    var left, right: [8] Simd.F32x4
    var frequencies: [8] u64
    var activeRows = 0'u64
    let half = Simd.splat(0.5'f32)
    for y in 8'u64
    {
        var lo, hi: Simd.F32x4
        var active = false
        for u in 8'u64
        {
            let value = block[][y * 8 + u]
            if not value do
                continue
            active = true
            let coefficient = Simd.splat(cast(f32, value))
            lo += coefficient * Simd.load(&g_Cosines[u, 0])
            hi += coefficient * Simd.load(&g_Cosines[u, 4])
        }

        if active
        {
            frequencies[activeRows] = y
            left[activeRows]        = lo * half
            right[activeRows]       = hi * half
            activeRows += 1
        }
    }

    // Without vertical AC, each output row has the same samples.
    let rows = activeRows == 0 or (activeRows == 1 and frequencies[0] == 0) ? 1'u64 : 8'u64
    for y in rows
    {
        var lo, hi: Simd.F32x4
        for v in activeRows
        {
            let coefficient = Simd.splat(g_Cosines[frequencies[v], y])
            lo += left[v] * coefficient
            hi += right[v] * coefficient
        }

        for x in 4'u64
        {
            output[][y * 8 + x]     = cast(s16, Math.clamp(cast(s32, Math.round(lo[x] * 0.5)), -512's32, 511's32))
            output[][y * 8 + x + 4] = cast(s16, Math.clamp(cast(s32, Math.round(hi[x] * 0.5)), -512's32, 511's32))
        }
    }

    if rows == 1
    {
        const RowBytes = 8 * #sizeof(s16)
        for y in 1'u64 until 8'u64 do
            Memory.copy(&output[][y * 8], &output[][0], RowBytes)
    }
}
