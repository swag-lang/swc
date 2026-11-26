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
        // The H.263 method, clause 7.4.4.2. Preserve the intra DC outside the AC scaling.
        let dc    = block[][0]
        let step  = Simd.splat(cast(s32, quant) * 2)
        let bias  = Simd.splat(cast(s32, quant) - (quant & 1 ? 0 : 1))
        let zero  = Simd.splat(0's32)
        let lower = Simd.splat(CoefficientFloor)
        let upper = Simd.splat(CoefficientCeil)
        for index in 16'u64
        {
            let levels    = Simd.load(&block[][index * 4])
            let sign      = levels >> 31'u32
            let magnitude = Math.abs(levels) * step + bias
            let scaled    = ((magnitude ^ sign) - sign) & cast #bit(Simd.S32x4, levels != zero)
            Simd.store(&block[][index * 4], Math.clamp(scaled, lower, upper))
        }

        if intra do
            block[][0] = dc

        return
    }

    // For the ordinary five-bit quantizer the weighted intermediate fits in signed 32 bits.
    if quant <= 31
    {
        dequantiseWeighted(block, layer, quant, intra)
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

// Divide the weighted magnitude before restoring its sign to round toward zero.
private func dequantiseWeighted(block: *[64] s32, layer: const *Layer, quant: u32, intra: bool)
{
    let weights: const [..] u8 = intra ? layer.intraMatrix : layer.interMatrix
    let dc    = block[][0]
    let step  = Simd.splat(cast(s32, quant))
    let bias  = Simd.splat(intra ? 0's32 : 1's32)
    let zero  = Simd.splat(0's32)
    let lower = Simd.splat(CoefficientFloor)
    let upper = Simd.splat(CoefficientCeil)
    var parity:  Simd.U32x4
    for index in 16'u64
    {
        let offset  = index * 4
        let bytes   = cast #bit(Simd.U8x16, Simd.splat(cast(const [*] u32, weights.buffer + offset)[0]))
        let weight  = cast #bit(Simd.S32x4, Simd.widenLow(Simd.widenLow(bytes)))
        let levels  = Simd.load(&block[][offset])
        let sign    = levels >> 31'u32
        let product = ((Math.abs(levels) * 2 + bias) * weight * step) >> 4'u32
        let scaled  = ((product ^ sign) - sign) & cast #bit(Simd.S32x4, levels != zero)
        let result  = Math.clamp(scaled, lower, upper)

        // The low bit of an XOR matches the low bit of the sum.
        parity ^= cast #bit(Simd.U32x4, result)
        Simd.store(&block[][offset], result)
    }

    if intra do
        block[][0] = Math.clamp(dc, CoefficientFloor, CoefficientCeil)
    elif not (Simd.bitwiseXor(parity) & 1) do
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

// Keep the two floating-point transform passes and their exact rounding at half samples.
private const DcSamples = #run buildDcSamples()

private func buildDcSamples()->[CoefficientCeil + 1] u8
{
    var samples: #returntype
    let cosines = buildCosines()
    let basis   = cosines[0, 0]
    for coefficient in samples.count
    {
        let row   = cast(f32, coefficient) * basis * 0.5'f32
        let value = cast(s32, Math.round(row * basis * 0.5'f32))
        samples[coefficient] = cast(u8, Math.clamp(value, 0's32, 255's32))
    }

    return samples
}

// Outside the table the inverse transform saturates to zero or 255.
func dcSample(coefficient: s32)->u8
{
    let index = Math.clamp(coefficient, 0's32, CoefficientCeil)
    return DcSamples[cast(u64, index)]
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
    let half       = Simd.splat(0.5'f32)
    let zero       = Simd.splat(0's32)
    for y in 8'u64
    {
        let row  = cast(const [*] s32, &block[][y * 8])
        let low  = Simd.bitmask(Simd.load(row) != zero)
        let high = Simd.bitmask(Simd.load(row + 4) != zero)
        var mask = low | (high << 4)
        if not mask do
            continue

        var lo, hi: Simd.F32x4
        while mask
        {
            let u = Swag.trailingZeros(mask)
            mask &= mask - 1
            let coefficient = Simd.splat(cast(f32, row[u]))
            lo += coefficient * Simd.load(&g_Cosines[u, 0])
            hi += coefficient * Simd.load(&g_Cosines[u, 4])
        }

        frequencies[activeRows] = y
        left[activeRows]        = lo * half
        right[activeRows]       = hi * half
        activeRows              += 1
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

        let low     = Simd.truncateToS32(Math.round(lo * half))
        let high    = Simd.truncateToS32(Math.round(hi * half))
        let samples = Math.clamp(Simd.packSigned(low, high), Simd.splat(-512's16), Simd.splat(511's16))
        Simd.store(&output[][y * 8], samples)
    }

    if rows == 1
    {
        let samples = Simd.load(&output[][0])
        for y in 1'u64 until 8'u64 do
            Simd.store(&output[][y * 8], samples)
    }
}
