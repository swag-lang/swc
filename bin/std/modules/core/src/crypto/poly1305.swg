#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

using Math

// Size in bytes of a Poly1305 one-time key.
public const Poly1305KeySize = 32

// Size in bytes of a Poly1305 authentication tag.
public const Poly1305TagSize = 16

// Size in bytes of one Poly1305 input block.
public const Poly1305BlockSize = 16

// Stores a Poly1305 authentication tag.
public alias Poly1305Tag = [Poly1305TagSize] u8

private const LimbMask                 = 0x3FF_FFFF_u64
private const ScalarWideBlockThreshold = 8
private const IfmaBlockThreshold = 20
private const TileBlockBits = 13
private const TileBlocks = 1 << TileBlockBits
private const TileSize = TileBlocks * Poly1305BlockSize

#[Swag.Inline]
private func load32Le(data: const [*] u8)->u64
{
    return Math.littleEndianToNative(cast(const [*] u32, data)[0])
}

#[Swag.Inline]
private func(T) poly1305LimbProduct(left, right: T)->T
{
    #static if T == u64
    {
        return left * right
    }
    else
    {
        // A limb and its scaled coefficient fit in 32 bits each.
        const mask = cast(Simd.U64x2, [0xFFFF_FFFF_u64, 0xFFFF_FFFF])
        return (left & mask) * (right & mask)
    }
}

#[Swag.Inline]
private func(T) poly1305Multiply(h, r, scaled: [5] T, result: *[5] T)
{
    result[][0] = poly1305LimbProduct(h[0], r[0]) + poly1305LimbProduct(h[1], scaled[4]) +
                  poly1305LimbProduct(h[2], scaled[3]) + poly1305LimbProduct(h[3], scaled[2]) + poly1305LimbProduct(h[4], scaled[1])
    result[][1] = poly1305LimbProduct(h[0], r[1]) + poly1305LimbProduct(h[1], r[0]) +
                  poly1305LimbProduct(h[2], scaled[4]) + poly1305LimbProduct(h[3], scaled[3]) + poly1305LimbProduct(h[4], scaled[2])
    result[][2] = poly1305LimbProduct(h[0], r[2]) + poly1305LimbProduct(h[1], r[1]) +
                  poly1305LimbProduct(h[2], r[0]) + poly1305LimbProduct(h[3], scaled[4]) + poly1305LimbProduct(h[4], scaled[3])
    result[][3] = poly1305LimbProduct(h[0], r[3]) + poly1305LimbProduct(h[1], r[2]) +
                  poly1305LimbProduct(h[2], r[1]) + poly1305LimbProduct(h[3], r[0]) + poly1305LimbProduct(h[4], scaled[4])
    result[][4] = poly1305LimbProduct(h[0], r[4]) + poly1305LimbProduct(h[1], r[3]) +
                  poly1305LimbProduct(h[2], r[2]) + poly1305LimbProduct(h[3], r[1]) + poly1305LimbProduct(h[4], r[0])
}

#[Swag.Inline]
private func poly1305Carry(h: *[5] u64, products: const *[5] u64)
{
    let first  = products[][0]
    let second = products[][1] + (first >> 26)
    let third  = products[][2] + (second >> 26)
    let fourth = products[][3] + (third >> 26)
    let fifth  = products[][4] + (fourth >> 26)
    let low    = (first & LimbMask) + (fifth >> 26) * 5
    h[][0] = low & LimbMask
    h[][1] = (second & LimbMask) + (low >> 26)
    h[][2] = third & LimbMask
    h[][3] = fourth & LimbMask
    h[][4] = fifth & LimbMask
}

#[Swag.Inline]
private func poly1305LoadPair(words: const [*] u64)->[5] Simd.U64x2
{
    let first  = Simd.load(words)
    let second = Simd.load(words + 2)
    let low    = Simd.interleaveLow(first, second)
    let high   = Simd.interleaveHigh(first, second)
    return [
        low & LimbMask,
        (low >> 26) & LimbMask,
        ((low >> 52) | (high << 12)) & LimbMask,
        (high >> 14) & LimbMask,
        (high >> 40) | (1_u64 << 24)]
}

#[Swag.Inline]
private func poly1305MultiplyReduced(left, right: [5] u64)->[5] u64
{
    var scratch: struct
    {
        scaled, products: [5] u64
    }
    for index in 1 to 4
    {
        scratch.scaled[index] = right[index] * 5
    }

    poly1305Multiply(left, right, scratch.scaled, &scratch.products)
    var result: #returntype
    poly1305Carry(&result, &scratch.products)
    secureClear(Swag.makeSlice(&scratch, 1))
    return result
}

private const Limb44Mask = (1_u64 << 44) - 1
private const Limb42Mask = (1_u64 << 42) - 1
private alias Poly44Lanes = [3] Simd.U64x2

private struct Poly44Products
{
    low, high: Poly44Lanes
}

#[Swag.Inline]
private func poly44FromLimbs(limbs: [5] u64)->[3] u64
{
    // Carry bit offsets while changing radix, including any loose limb.
    let low = limbs[0] + (limbs[1] << 26)
    let mid = (low >> 44) + (limbs[2] << 8) + (limbs[3] << 34)
    let top = (mid >> 44) + (limbs[4] << 16)
    return [low & Limb44Mask, mid & Limb44Mask, top]
}

#[Swag.Inline]
private func poly44ToLimbs(limbs: [3] u64)->[5] u64
{
    // The carry out of bit 130 after adding five selects the final subtraction.
    let quotient = (limbs[2] + ((limbs[1] + ((limbs[0] + 5) >> 44)) >> 44)) >> 42
    let first    = limbs[0] + quotient * 5
    let second   = limbs[1] + (first >> 44)
    let third    = (limbs[2] + (second >> 44)) & Limb42Mask
    let low      = first & Limb44Mask
    let mid      = second & Limb44Mask
    return [low & LimbMask, ((low >> 26) | (mid << 18)) & LimbMask, (mid >> 8) & LimbMask,
            ((mid >> 34) | (third << 10)) & LimbMask, third >> 16]
}

#[Swag.Inline]
private func poly44LoadPair(words: const [*] u64)->Poly44Lanes
{
    let first  = Simd.load(words)
    let second = Simd.load(words + 2)
    let low    = Simd.interleaveLow(first, second)
    let high   = Simd.interleaveHigh(first, second)
    return [low & Limb44Mask, ((low >> 44) | (high << 20)) & Limb44Mask, (high >> 24) | (1_u64 << 40)]
}

#[Swag.Inline]
private func poly44Scale(factor: Poly44Lanes)->[2] Simd.U64x2
{
    // Base^3 is four times 2^130, so wrapped terms multiply by 20.
    return [(factor[1] << 4) + (factor[1] << 2), (factor[2] << 4) + (factor[2] << 2)]
}

#[Swag.Mixin]
private func poly44Accumulate(index: u64, a0, b0, a1, b1, a2, b2: Simd.U64x2)
{
    // Three low or high halves, even summed across both lanes, fit in u64.
    product.low[index] = Swag.vecMultiplyAdd52Low(Swag.vecMultiplyAdd52Low(Swag.vecMultiplyAdd52Low(zero, a0, b0),
                                                                           a1,
                                                                           b1),
                                                  a2,
                                                  b2)
    product.high[index] = Swag.vecMultiplyAdd52High(Swag.vecMultiplyAdd52High(Swag.vecMultiplyAdd52High(zero, a0, b0),
                                                                              a1,
                                                                              b1),
                                                    a2,
                                                    b2)
}

#[Swag.Inline]
private func poly44Multiply(left, right: Poly44Lanes, scaled: [2] Simd.U64x2, product: *Poly44Products)
{
    let zero = Simd.splat(0_u64)

    poly44Accumulate(0, left[0], right[0], left[1], scaled[1], left[2], scaled[0])
    poly44Accumulate(1, left[0], right[1], left[1], right[0], left[2], scaled[1])
    poly44Accumulate(2, left[0], right[2], left[1], right[1], left[2], right[0])
}

#[Swag.Inline]
private func(T) poly44Carry(low, high: [3] T, result: *[3] T)
{
    let mid   = low[1] + (low[0] >> 44) + (high[0] << 8)
    let top   = low[2] + (mid >> 44) + (high[1] << 8)
    let carry = (top >> 42) + (high[2] << 10)
    let first = (low[0] & Limb44Mask) + carry + (carry << 2)
    result[][0] = first & Limb44Mask
    result[][1] = (mid & Limb44Mask) + (first >> 44)
    result[][2] = top & Limb42Mask
}

#[Swag.Inline]
private func(High: bool) poly44Dot(a0, b0, a1, b1, a2, b2: Simd.U64x2)->Simd.U64x2
{
    let zero = Simd.splat(0_u64)
    #static if High
    {
        return Swag.vecMultiplyAdd52High(Swag.vecMultiplyAdd52High(Swag.vecMultiplyAdd52High(zero, a0, b0), a1, b1), a2, b2)
    }
    else
    {
        return Swag.vecMultiplyAdd52Low(Swag.vecMultiplyAdd52Low(Swag.vecMultiplyAdd52Low(zero, a0, b0), a1, b1), a2, b2)
    }
}

#[Swag.Inline]
private func poly44Pairs(words: const [*] u64, count: u64, state: *Poly44Lanes, factor: Poly44Lanes, scaled: [2] Simd.U64x2)
{
    var first  = state[][0]
    var middle = state[][1]
    var top    = state[][2]
    let r0     = factor[0]
    let r1     = factor[1]
    let r2     = factor[2]
    let s1     = scaled[0]
    let s2     = scaled[1]
    for pair in count
    {
        let left  = Simd.load(words + pair * 4)
        let right = Simd.load(words + pair * 4 + 2)
        let low   = Simd.interleaveLow(left, right)
        let high  = Simd.interleaveHigh(left, right)
        let a0    = first + (low & Limb44Mask)
        let a1    = middle + (((low >> 44) | (high << 20)) & Limb44Mask)
        let a2    = top + ((high >> 24) | (1_u64 << 40))

        let p0   = poly44Dot!{false}(a0, r0, a1, s2, a2, s1)
        let h0   = poly44Dot!{true}(a0, r0, a1, s2, a2, s1)
        let p1   = poly44Dot!{false}(a0, r1, a1, r0, a2, s2)
        let h1   = poly44Dot!{true}(a0, r1, a1, r0, a2, s2)
        let p2   = poly44Dot!{false}(a0, r2, a1, r1, a2, r0)
        let h2   = poly44Dot!{true}(a0, r2, a1, r1, a2, r0)
        let d1   = p1 + (h0 << 8)
        let d2   = p2 + (h1 << 8)
        let wrap = (d2 >> 42) + (h2 << 10)
        let d0   = (p0 & Limb44Mask) + wrap + (wrap << 2)
        first  = d0 & Limb44Mask
        middle = (d1 & Limb44Mask) + (p0 >> 44) + (d0 >> 44)
        top    = (d2 & Limb42Mask) + (d1 >> 44)
    }

    state[][0] = first
    state[][1] = middle
    state[][2] = top
}

#[Swag.Inline]
private func poly64FromLimbs(limbs: [5] u64)->[3] u64
{
    let first = limbs[0] + (limbs[1] << 26)
    let low = first + (limbs[2] << 52)
    let upper = limbs[4] << 40
    let middle = upper + (limbs[3] << 14) + (limbs[2] >> 12) + cast(u64, low < first)
    return [low, middle, (limbs[4] >> 24) + cast(u64, middle < upper)]
}

#[Swag.Inline]
private func poly64Reduce(limbs: [3] u64)->[3] u64
{
    // The carry from adding five across bit 130 selects subtraction of the modulus.
    let lowPlusFive     = limbs[0] + 5
    let middlePlusCarry = limbs[1] + cast(u64, lowPlusFive < limbs[0])
    let quotient        = (limbs[2] + cast(u64, middlePlusCarry < limbs[1])) >> 2
    let low             = limbs[0] + quotient * 5
    let middle          = limbs[1] + cast(u64, low < limbs[0])
    let high            = (limbs[2] + cast(u64, middle < limbs[1])) & 3
    return [low, middle, high]
}

#[Swag.Inline]
private func poly64ToLimbs(limbs: [3] u64)->[5] u64
{
    let reduced = poly64Reduce(limbs)
    let low     = reduced[0]
    let middle  = reduced[1]
    let high    = reduced[2]
    return [low & LimbMask, (low >> 26) & LimbMask, ((low >> 52) | (middle << 12)) & LimbMask,
            (middle >> 14) & LimbMask, (middle >> 40) | (high << 24)]
}

private struct Poly1305WordState
{
    accumulator: [3] u64
    key:         [3] u64
    wrapped:     u64
}

#[Swag.Inline]
private func poly64Absorb(state: *Poly1305WordState, data: const [*] u64, highBit: u64)
{
    let low  = Math.littleEndianToNative(data[0])
    let high = Math.littleEndianToNative(data[1])
    let a0   = state.accumulator[0] + low
    let mid  = state.accumulator[1] + high
    let a1   = mid + cast(u64, a0 < state.accumulator[0])
    let a2   = state.accumulator[2] + highBit + cast(u64, mid < state.accumulator[1]) + cast(u64, a1 < mid)

    let product00 = Math.mulU64(a0, state.key[0])
    let product01 = Math.mulU64(a0, state.key[1])
    var carry0, carry1: u64
    let d0        = Swag.mulWide(a1, state.wrapped, product00.lo, 0, &carry0)

    // The top limb is at most six and the clamped key bounds this sum below one word.
    let advance = product00.hi + carry0 + a2 * state.wrapped
    let d1      = Swag.mulWide(a1, state.key[0], product01.lo, advance, &carry1)
    let d2      = a2 * state.key[0] + product01.hi + carry1
    let first   = d0 + ((d2 & ~3_u64) + (d2 >> 2))
    let second  = d1 + cast(u64, first < d0)
    state.accumulator[0] = first
    state.accumulator[1] = second
    state.accumulator[2] = (d2 & 3) + cast(u64, second < d1)
}

#[Swag.Inline]
private func poly64Tag(reduced: [3] u64, padLow, padHigh: u64)->Poly1305Tag
{
    let low   = reduced[0] + padLow
    let high  = reduced[1] + padHigh + cast(u64, low < reduced[0])
    var result: #returntype
    let words = cast([*] u64, result.buffer)
    words[0] = Math.nativeToLittleEndian(low)
    words[1] = Math.nativeToLittleEndian(high)
    return result
}

private func computeSmallPoly1305(key: const [*] u8, data: const [..] u8)->Poly1305Tag
{
    var scratch: struct
    {
        state:   Poly1305WordState
        partial: [Poly1305BlockSize] u8
        reduced: [3] u64
        pad:     [2] u64
    }
    defer secureClear(Swag.makeSlice(&scratch, 1))
    with scratch
    {
        let keyWords = cast(const [*] u64, key)
        .state.key[0]  = Math.littleEndianToNative(keyWords[0]) & 0x0FFF_FFFC_0FFF_FFFF
        .state.key[1]  = Math.littleEndianToNative(keyWords[1]) & 0x0FFF_FFFC_0FFF_FFFC
        .state.wrapped = .state.key[1] + (.state.key[1] >> 2)

        let blocks = data.count / Poly1305BlockSize
        let words  = cast(const [*] u64, data.buffer)
        for block in blocks
        {
            poly64Absorb(&.state, words + block * 2, 1)
        }

        let remaining = data.count % Poly1305BlockSize
        if remaining
        {
            Swag.memcpy(.partial.buffer, data.buffer + blocks * Poly1305BlockSize, remaining)
            .partial[remaining] = 1
            poly64Absorb(&.state, cast(const [*] u64, .partial.buffer), 0)
        }

        .reduced = poly64Reduce(.state.accumulator)
        .pad[0]  = Math.littleEndianToNative(keyWords[2])
        .pad[1]  = Math.littleEndianToNative(keyWords[3])
        return poly64Tag(.reduced, .pad[0], .pad[1])
    }
}

private func checkPoly1305Key(key: const [..] u8) fail
{
    if key.count != Poly1305KeySize
    {
        fail Errors.BadParameterError{"Poly1305 needs a 32-byte key"}
    }
}

// Authenticates a message under a one-time key, following RFC 8439.
//
// A Poly1305 key authenticates exactly one message. Reusing it across two
// messages lets an observer recover the key material and forge tags, which is
// why [[Core.Crypto.chacha20Poly1305Seal]] derives a fresh one from each nonce.
#[Swag.NoCopy]
#[Swag.Opaque]
public struct Poly1305
{
    r:           [5] u64
    pad:         [4] u64
    accumulator: [5] u64
    buffer:      [Poly1305BlockSize] u8
    bufferCount: u64
    initialized: bool
}

public impl Poly1305
{
    // Creates a sequence keyed by the 32-byte one-time key `key`.
    func create(key: const [..] u8)->Poly1305 fail
    {
        var result: #returntype
        try result.reset(key)
        return result
    }

    // Replaces any previous state and starts a new sequence for the 32-byte one-time key `key`.
    //
    // Fails with [[Core.Errors.BadParameterError]] when `key` does not hold 32 bytes.
    mtd reset(key: const [..] u8) fail
    {
        try checkPoly1305Key(key)

        if .initialized
        {
            .clear()

            // The first half of the key is clamped: the masks are what keep every
            // partial product inside the range the limb arithmetic below assumes.
        }

        let t0 = load32Le(key.buffer)
        let t1 = load32Le(key.buffer + 4)
        let t2 = load32Le(key.buffer + 8)
        let t3 = load32Le(key.buffer + 12)
        .r[0] = t0 & 0x3FF_FFFF
        .r[1] = ((t0 >> 26) | (t1 << 6)) & 0x3FF_FF03
        .r[2] = ((t1 >> 20) | (t2 << 12)) & 0x3FF_C0FF
        .r[3] = ((t2 >> 14) | (t3 << 18)) & 0x3F0_3FFF
        .r[4] = (t3 >> 8) & 0x00F_FFFF

        // The second half is added once, at finalization.
        for i in 4
        {
            .pad[i] = load32Le(key.buffer + Poly1305BlockSize + i * 4)
        }

        .initialized = true
    }

    // Includes `data` in the running authentication code.
    mtd update(data: const [..] u8)
    {
        Swag.assert(.initialized, "Poly1305 needs an initialized sequence")

        if not data.count
        {
            return
        }

        var offset = 0_u64

        // Finish a block carried by a previous update before reading whole blocks in place.
        if .bufferCount
        {
            offset = Math.min(data.count, Poly1305BlockSize - .bufferCount)
            Swag.memcpy(&.buffer[.bufferCount], data.buffer, offset)
            .bufferCount += offset
            if .bufferCount < Poly1305BlockSize
            {
                return
            }

            .absorbBlocks(.buffer.buffer, 1, 1 << 24)
            .bufferCount = 0
        }

        var blocks = (data.count - offset) / Poly1305BlockSize
        #static if not BIG_ENDIAN
        {
            let useIfma = blocks >= IfmaBlockThreshold and Swag.hasCpuFeature(.MultiplyAdd52)
            if blocks >= 2 * TileBlocks and Swag.workerCount() > 1
            {
                let tiles = blocks / TileBlocks
                .absorbTiles(data.buffer + offset, tiles, useIfma)
                offset += tiles * TileSize
                blocks %= TileBlocks
            }

            // Precompute the powers once for a run of full input blocks.
            const QuadBlockThreshold = 64
            if useIfma and blocks >= IfmaBlockThreshold
            {
                let pairs = blocks / 2
                .absorbIfmaPairs(data.buffer + offset, pairs)
                offset += pairs * 2 * Poly1305BlockSize
                blocks &= 1
            }
            else if blocks >= QuadBlockThreshold
            {
                let quads = blocks / 4
                .absorbQuads(data.buffer + offset, quads)
                offset += quads * 4 * Poly1305BlockSize
                blocks &= 3
            }
        }

        if blocks
        {
            .absorbBlocks(data.buffer + offset, blocks, 1 << 24)
            offset += blocks * Poly1305BlockSize
        }

        if offset < data.count
        {
            .bufferCount = data.count - offset
            Swag.memcpy(.buffer.buffer, data.buffer + offset, .bufferCount)
        }
    }

    // Finalizes the sequence, returns its authentication tag, and clears the keyed state.
    //
    // Call [[Core.Crypto.Poly1305.reset]] before reusing this value.
    mtd finalize()->Poly1305Tag
    {
        Swag.assert(.initialized, "Poly1305 needs an initialized sequence")

        // A partial block carries its terminator inside the block itself, which
        // is what separates a short message from a padded longer one.
        if .bufferCount
        {
            .buffer[.bufferCount] = 1
            Swag.memset(.buffer.buffer + .bufferCount + 1, 0, Poly1305BlockSize - .bufferCount - 1)
            .absorbBlocks(.buffer.buffer, 1, 0)
            .bufferCount = 0
        }

        var reduced = poly64Reduce(poly64FromLimbs(.accumulator))
        let padLow  = .pad[0] | (.pad[1] << 32)
        let padHigh = .pad[2] | (.pad[3] << 32)
        let result  = poly64Tag(reduced, padLow, padHigh)

        secureClear(reduced)
        .clear()
        return result
    }

    // Clears all keyed state held by this value.
    mtd clear()
    {
        // Every field is zero-initialized and the state contains no owned resources.
        secureClear(Swag.makeSlice(me, 1))
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        if .initialized
        {
            .clear()
        }
    }

    // Computes the Poly1305 tag of `data` under `key` in one operation.
    func compute(key, data: const [..] u8)->Poly1305Tag fail
    {
        if data.count < IfmaBlockThreshold * Poly1305BlockSize
        {
            try checkPoly1305Key(key)
            return computeSmallPoly1305(key.buffer, data)
        }

        var mac = try Poly1305.create(key)
        mac.update(data)
        return mac.finalize()
    }

    private mtd absorbScalar64(blocks: const [*] u8, count: u64)
    {
        var state: Poly1305WordState
        state.accumulator = poly64FromLimbs(.accumulator)
        state.key = poly64FromLimbs(.r)
        state.wrapped = state.key[1] + (state.key[1] >> 2)

        let words = cast(const [*] u64, blocks)
        for block in count
        {
            poly64Absorb(&state, words + block * 2, 1)
        }

        .accumulator = poly64ToLimbs(state.accumulator)
        secureClear(Swag.makeSlice(&state, 1))
    }

    // The implicit high bit belongs to each full block. Finalization supplies a
    // zero high bit because the padded final block already contains its terminator.
    private mtd absorbBlocks(blocks: const [*] u8, count, highBit: u64)
    {
        if count >= ScalarWideBlockThreshold
        {
            .absorbScalar64(blocks, count)
            return
        }

        // Terms that wrap past 2^130 pick up a factor of five modulo 2^130 - 5.
        var scratch: struct
        {
            scaled, h, d: [5] u64
        }
        with scratch
        {
            for i in 1 to 4
            {
                .scaled[i] = me.r[i] * 5
            }

            .h = me.accumulator
            for block in count
            {
                let data = cast(const [*] u64, blocks + block * Poly1305BlockSize)
                let low  = Math.littleEndianToNative(data[0])
                let high = Math.littleEndianToNative(data[1])
                .h[0] += low & LimbMask
                .h[1] += (low >> 26) & LimbMask
                .h[2] += ((low >> 52) | (high << 12)) & LimbMask
                .h[3] += (high >> 14) & LimbMask
                .h[4] += (high >> 40) | highBit

                .d[0] = .h[0] * me.r[0] + .h[1] * .scaled[4] + .h[2] * .scaled[3] + .h[3] * .scaled[2] + .h[4] * .scaled[1]
                .d[1] = .h[0] * me.r[1] + .h[1] * me.r[0] + .h[2] * .scaled[4] + .h[3] * .scaled[3] + .h[4] * .scaled[2]
                .d[2] = .h[0] * me.r[2] + .h[1] * me.r[1] + .h[2] * me.r[0] + .h[3] * .scaled[4] + .h[4] * .scaled[3]
                .d[3] = .h[0] * me.r[3] + .h[1] * me.r[2] + .h[2] * me.r[1] + .h[3] * me.r[0] + .h[4] * .scaled[4]
                .d[4] = .h[0] * me.r[4] + .h[1] * me.r[3] + .h[2] * me.r[2] + .h[3] * me.r[1] + .h[4] * me.r[0]

                poly1305Carry(&.h, &.d)
            }

            me.accumulator = .h
        }

        secureClear(Swag.makeSlice(&scratch, 1))
    }

    private mtd absorbQuads(blocks: const [*] u8, count: u64)
    {
        // Expand four successive blocks into two products per lane. Every
        // fourth block shares the same carry across the four contributions.
        var scratch: struct
        {
            squared, cubed, fourth: [5] u64
            firstFactors, firstWrapped, secondFactors, secondWrapped: [5] Simd.U64x2
            first, second, firstProducts, secondProducts: [5] Simd.U64x2
            h, products: [5] u64
        }

        with scratch
        {
            .squared = poly1305MultiplyReduced(me.r, me.r)
            .cubed   = poly1305MultiplyReduced(.squared, me.r)
            .fourth  = poly1305MultiplyReduced(.squared, .squared)
            for i in 5
            {
                .firstFactors[i]  = cast(Simd.U64x2, [.fourth[i], .cubed[i]])
                .firstWrapped[i]  = cast(Simd.U64x2, [.fourth[i] * 5, .cubed[i] * 5])
                .secondFactors[i] = cast(Simd.U64x2, [.squared[i], me.r[i]])
                .secondWrapped[i] = cast(Simd.U64x2, [.squared[i] * 5, me.r[i] * 5])
            }

            .h = me.accumulator
            for group in count
            {
                let words = cast(const [*] u64, blocks + group * 4 * Poly1305BlockSize)
                .first  = poly1305LoadPair(words)
                .second = poly1305LoadPair(words + 4)
                for i in 5
                {
                    .first[i] += cast(Simd.U64x2, [.h[i], 0_u64])
                }

                poly1305Multiply(.first, .firstFactors, .firstWrapped, &.firstProducts)
                poly1305Multiply(.second, .secondFactors, .secondWrapped, &.secondProducts)
                for i in 5
                {
                    .products[i] = Simd.sum(.firstProducts[i] + .secondProducts[i])
                }

                poly1305Carry(&.h, &.products)
            }

            me.accumulator = .h
        }

        secureClear(Swag.makeSlice(&scratch, 1))
    }

    private mtd absorbIfmaPairs(blocks: const [*] u8, count: u64)
    {
        // Accumulate alternate blocks independently with r^2. The final
        // multiplication advances the two lanes by r^2 and r respectively.
        var scratch: struct
        {
            uniform, final, state, message:  Poly44Lanes
            uniformScaled, finalScaled:      [2] Simd.U64x2
            key, initial, low, high, result: [3] u64
            product: Poly44Products
        }

        with scratch
        {
            .key     = poly44FromLimbs(me.r)
            .initial = poly44FromLimbs(me.accumulator)
            for limb in 3
            {
                .uniform[limb] = Simd.splat(.key[limb])
                .state[limb]   = cast(Simd.U64x2, [.initial[limb], 0_u64])
            }

            poly44Multiply(.uniform, .uniform, poly44Scale(.uniform), &.product)
            poly44Carry(.product.low, .product.high, &.uniform)
            for limb in 3
            {
                .final[limb] = cast(Simd.U64x2, [cast([2] u64, .uniform[limb])[0], .key[limb]])
            }

            .uniformScaled = poly44Scale(.uniform)
            .finalScaled   = poly44Scale(.final)

            let words = cast(const [*] u64, blocks)
            poly44Pairs(words, count - 1, &.state, .uniform, .uniformScaled)
            .message = poly44LoadPair(words + (count - 1) * 4)
            for limb in 3
            {
                .state[limb] += .message[limb]
            }

            poly44Multiply(.state, .final, .finalScaled, &.product)
            for limb in 3
            {
                .low[limb]  = Simd.sum(.product.low[limb])
                .high[limb] = Simd.sum(.product.high[limb])
            }

            poly44Carry(.low, .high, &.result)
            me.accumulator = poly44ToLimbs(.result)
        }

        secureClear(Swag.makeSlice(&scratch, 1))
    }

    private mtd absorbTiles(bytes: const [*] u8, tileCount: u64, useIfma: bool)
    {
        // A tile can start with zero and run independently. Concatenation
        // advances the running accumulator by r^TileBlocks, then adds the tile.
        const MaxTiles = 32
        let key     = &.r
        var advance = .r
        for TileBlockBits
        {
            advance = poly1305MultiplyReduced(advance, advance)
        }

        var results: [MaxTiles][5] u64
        var sum:     [5] u64
        var processed = 0_u64
        while processed < tileCount
        {
            let count  = Math.min(tileCount - processed, MaxTiles)
            let source = bytes + processed * TileSize
            parallel for |source, key, &results, useIfma| tile in count
            {
                var state: Poly1305
                state.r = key[]
                if useIfma
                {
                    state.absorbIfmaPairs(source + tile * TileSize, TileBlocks / 2)
                }
                else
                {
                    state.absorbQuads(source + tile * TileSize, TileBlocks / 4)
                }

                results[tile] = state.accumulator
                state.clear()
            }

            for tile in count
            {
                .accumulator = poly1305MultiplyReduced(.accumulator, advance)
                for limb in sum.count
                {
                    sum[limb] = .accumulator[limb] + results[tile][limb]
                }

                poly1305Carry(&.accumulator, &sum)
            }

            processed += count
        }

        secureClear(results)
        secureClear(advance)
        secureClear(sum)
    }
}
