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
private func poly1305Carry(h, products: *[5] u64)
{
    var carry = 0'u64
    for i in 5
    {
        products[][i] += carry
        carry         = products[][i] >> 26
        h[][i]        = products[][i] & LimbMask
    }

    h[][0] += carry * 5
    carry  = h[][0] >> 26
    h[][0] &= LimbMask
    h[][1] += carry
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
            // Preparing r^2 pays off once the update contains a full run of blocks.
            const PairedBlockThreshold = 128
            if blocks >= PairedBlockThreshold
            {
                let pairs = blocks / 2
                .absorbPairs(data.buffer + offset, pairs)
                offset += pairs * 2 * Poly1305BlockSize
                blocks &= 1
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

                var carry = 0'u64
                for i in 5
                {
                    .d[i]  += carry
                    carry = .d[i] >> 26
                    .h[i]  = .d[i] & LimbMask
                }

                .h[0]  += carry * 5
                carry = .h[0] >> 26
                .h[0]  &= LimbMask
                .h[1]  += carry
            }

            me.accumulator = .h
        }
        secureClear(Swag.makeSlice(&scratch, 1))
    }

    private mtd absorbPairs(blocks: const [*] u8, count: u64)
    {
        // Two successive blocks update h as (h + m0) * r^2 + m1 * r.
        // Keep those products in separate vector lanes until the shared carry.
        var scaled: [5] u64
        for i in 1 to 4 do
            scaled[i] = .r[i] * 5
        var squared = .r
        var products: [5] u64
        poly1305Multiply(.r, .r, scaled, &products)
        poly1305Carry(&squared, &products)

        var factors, wrapped: [5] Simd.U64x2
        for i in 5
        {
            factors[i] = cast(Simd.U64x2, [squared[i], .r[i]])
            wrapped[i] = cast(Simd.U64x2, [squared[i] * 5, scaled[i]])
        }

        var h = .accumulator
        var message, packedProducts: [5] Simd.U64x2
        for pair in count
        {
            let words  = cast(const [*] u64, blocks + pair * 2 * Poly1305BlockSize)
            let first  = Simd.load(words)
            let second = Simd.load(words + 2)
            let low    = Simd.interleaveLow(first, second)
            let high   = Simd.interleaveHigh(first, second)
            message[0] = low & LimbMask
            message[1] = (low >> 26) & LimbMask
            message[2] = ((low >> 52) | (high << 12)) & LimbMask
            message[3] = (high >> 14) & LimbMask
            message[4] = (high >> 40) | (1'u64 << 24)
            for i in 5 do
                message[i] += cast(Simd.U64x2, [h[i], 0'u64])

            poly1305Multiply(message, factors, wrapped, &packedProducts)
            for i in 5 do
                products[i] = Simd.sum(packedProducts[i])
            poly1305Carry(&h, &products)
        }

        .accumulator = h
        secureClear(h)
        secureClear(message)
        secureClear(packedProducts)
        secureClear(products)
        secureClear(factors)
        secureClear(wrapped)
        secureClear(squared)
        secureClear(scaled)
    }
}
