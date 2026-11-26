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

private const LimbMask = 0x3FF_FFFF'u64
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
        const mask = cast(Simd.U64x2, [0xFFFF_FFFF'u64, 0xFFFF_FFFF])
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
    let low = (first & LimbMask) + (fifth >> 26) * 5
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
        (high >> 40) | (1'u64 << 24)]
}

#[Swag.Inline]
private func poly1305MultiplyReduced(left, right: [5] u64)->[5] u64
{
    var scratch: struct
    {
        scaled, products: [5] u64
    }
    for index in 1 to 4 do
        scratch.scaled[index] = right[index] * 5
    poly1305Multiply(left, right, scratch.scaled, &scratch.products)
    var result: #returntype
    poly1305Carry(&result, &scratch.products)
    secureClear(Swag.makeSlice(&scratch, 1))
    return result
}

private const Limb44Mask = (1'u64 << 44) - 1
private const Limb42Mask = (1'u64 << 42) - 1
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
    let first = limbs[0] + quotient * 5
    let second = limbs[1] + (first >> 44)
    let third = (limbs[2] + (second >> 44)) & Limb42Mask
    let low = first & Limb44Mask
    let mid = second & Limb44Mask
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
    return [low & Limb44Mask, ((low >> 44) | (high << 20)) & Limb44Mask, (high >> 24) | (1'u64 << 40)]
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
                                                                           a1, b1), a2, b2)
    product.high[index] = Swag.vecMultiplyAdd52High(Swag.vecMultiplyAdd52High(Swag.vecMultiplyAdd52High(zero, a0, b0),
                                                                              a1, b1), a2, b2)
}

#[Swag.Inline]
private func poly44Multiply(left, right: Poly44Lanes, scaled: [2] Simd.U64x2, product: *Poly44Products)
{
    let zero = Simd.splat(0'u64)

    poly44Accumulate(0, left[0], right[0], left[1], scaled[1], left[2], scaled[0])
    poly44Accumulate(1, left[0], right[1], left[1], right[0], left[2], scaled[1])
    poly44Accumulate(2, left[0], right[2], left[1], right[1], left[2], right[0])
}

#[Swag.Inline]
private func(T) poly44Carry(low, high: [3] T, result: *[3] T)
{
    let mid = low[1] + (low[0] >> 44) + (high[0] << 8)
    let top = low[2] + (mid >> 44) + (high[1] << 8)
    let carry = (top >> 42) + (high[2] << 10)
    let first = (low[0] & Limb44Mask) + carry + (carry << 2)
    result[][0] = first & Limb44Mask
    result[][1] = (mid & Limb44Mask) + (first >> 44)
    result[][2] = top & Limb42Mask
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
        if key.count != Poly1305KeySize do
            fail Errors.BadParameterError{"Poly1305 needs a 32-byte key"}

        if .initialized do
            .clear()

        // The first half of the key is clamped: the masks are what keep every
        // partial product inside the range the limb arithmetic below assumes.
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
        for i in 4 do
            .pad[i] = load32Le(key.buffer + Poly1305BlockSize + i * 4)
        .initialized = true
    }

    // Includes `data` in the running authentication code.
    mtd update(data: const [..] u8)
    {
        Swag.assert(.initialized, "Poly1305 needs an initialized sequence")

        if not data.count do
            return

        var offset = 0'u64

        // Finish a block carried by a previous update before reading whole blocks in place.
        if .bufferCount
        {
            offset = Math.min(data.count, Poly1305BlockSize - .bufferCount)
            Swag.memcpy(&.buffer[.bufferCount], data.buffer, offset)
            .bufferCount += offset
            if .bufferCount < Poly1305BlockSize do
                return
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
            elif blocks >= QuadBlockThreshold
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

        var scratch: struct
        {
            h, g: [5] u64
        }
        scratch.h = .accumulator
        var result: #returntype
        with scratch
        {
            var carry = .h[1] >> 26
            .h[1] &= LimbMask
            for i in 2 to 4
            {
                .h[i]  += carry
                carry = .h[i] >> 26
                .h[i]  &= LimbMask
            }

            .h[0]  += carry * 5
            carry = .h[0] >> 26
            .h[0]  &= LimbMask
            .h[1]  += carry

            // Compute `h - p` and keep it only when it did not borrow, which is the
            // branch-free way to reduce the last time.
            .g[0]  = .h[0] + 5
            carry = .g[0] >> 26
            .g[0]  &= LimbMask
            for i in 1 to 3
            {
                .g[i]  = .h[i] + carry
                carry = .g[i] >> 26
                .g[i]  &= LimbMask
            }

            .g[4] = .h[4] + carry - (1 << 26)

            let borrowed = (.g[4] >> 63) & 1
            let keepG    = borrowed - 1
            let keepH    = ~keepG
            for i in 5 do
                .h[i] = (.h[i] & keepH) | (.g[i] & keepG)

            // Store the low 128 bits in two words and propagate the pad carry once.
            let low = .h[0] | (.h[1] << 26) | (.h[2] << 52)
            let high = (.h[2] >> 12) | (.h[3] << 14) | (.h[4] << 40)
            let padLow = me.pad[0] | (me.pad[1] << 32)
            let padHigh = me.pad[2] | (me.pad[3] << 32)
            let lowSum = low + padLow
            let highSum = high + padHigh + cast(u64, lowSum < low)
            let words = cast([*] u64, result.buffer)
            words[0] = Math.nativeToLittleEndian(lowSum)
            words[1] = Math.nativeToLittleEndian(highSum)
        }

        secureClear(Swag.makeSlice(&scratch, 1))
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
        if .initialized do
            .clear()
    }

    // Computes the Poly1305 tag of `data` under `key` in one operation.
    func compute(key, data: const [..] u8)->Poly1305Tag fail
    {
        var mac = try Poly1305.create(key)
        mac.update(data)
        return mac.finalize()
    }

    // The implicit high bit belongs to each full block. Finalization supplies a
    // zero high bit because the padded final block already contains its terminator.
    private mtd absorbBlocks(blocks: const [*] u8, count, highBit: u64)
    {
        // Terms that wrap past 2^130 pick up a factor of five modulo 2^130 - 5.
        var scratch: struct
        {
            scaled, h, d: [5] u64
        }
        with scratch
        {
            for i in 1 to 4 do
                .scaled[i] = me.r[i] * 5
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
                for i in 5 do
                    .first[i] += cast(Simd.U64x2, [.h[i], 0'u64])
                poly1305Multiply(.first, .firstFactors, .firstWrapped, &.firstProducts)
                poly1305Multiply(.second, .secondFactors, .secondWrapped, &.secondProducts)
                for i in 5 do
                    .products[i] = Simd.sum(.firstProducts[i] + .secondProducts[i])
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
            uniform, final, state, message: Poly44Lanes
            uniformScaled, finalScaled: [2] Simd.U64x2
            key, initial, low, high, result: [3] u64
            product: Poly44Products
        }

        with scratch
        {
            .key = poly44FromLimbs(me.r)
            .initial = poly44FromLimbs(me.accumulator)
            for limb in 3
            {
                .uniform[limb] = Simd.splat(.key[limb])
                .state[limb] = cast(Simd.U64x2, [.initial[limb], 0'u64])
            }

            poly44Multiply(.uniform, .uniform, poly44Scale(.uniform), &.product)
            poly44Carry(.product.low, .product.high, &.uniform)
            for limb in 3 do
                .final[limb] = cast(Simd.U64x2, [cast([2] u64, .uniform[limb])[0], .key[limb]])
            .uniformScaled = poly44Scale(.uniform)
            .finalScaled = poly44Scale(.final)

            var words = cast(const [*] u64, blocks)
            for count - 1
            {
                .message = poly44LoadPair(words)
                for limb in 3 do
                    .state[limb] += .message[limb]
                poly44Multiply(.state, .uniform, .uniformScaled, &.product)
                poly44Carry(.product.low, .product.high, &.state)
                words += 4
            }

            .message = poly44LoadPair(words)
            for limb in 3 do
                .state[limb] += .message[limb]
            poly44Multiply(.state, .final, .finalScaled, &.product)
            for limb in 3
            {
                .low[limb] = Simd.sum(.product.low[limb])
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
        let key = &.r
        var advance = .r
        for TileBlockBits do
            advance = poly1305MultiplyReduced(advance, advance)

        var results: [MaxTiles][5] u64
        var sum: [5] u64
        var processed = 0'u64
        while processed < tileCount
        {
            let count  = Math.min(tileCount - processed, MaxTiles)
            let source = bytes + processed * TileSize
            parallel for |source, key, &results, useIfma| tile in count
            {
                var state: Poly1305
                state.r = key[]
                if useIfma do
                    state.absorbIfmaPairs(source + tile * TileSize, TileBlocks / 2)
                else do
                    state.absorbQuads(source + tile * TileSize, TileBlocks / 4)
                results[tile] = state.accumulator
                state.clear()
            }

            for tile in count
            {
                .accumulator = poly1305MultiplyReduced(.accumulator, advance)
                for limb in sum.count do
                    sum[limb] = .accumulator[limb] + results[tile][limb]
                poly1305Carry(&.accumulator, &sum)
            }

            processed += count
        }

        secureClear(results)
        secureClear(advance)
        secureClear(sum)
    }
}
