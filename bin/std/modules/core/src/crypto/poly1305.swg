#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

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

        let blocks = (data.count - offset) / Poly1305BlockSize
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

        var h     = .accumulator
        var carry = h[1] >> 26
        h[1] &= LimbMask
        for i in 2 to 4
        {
            h[i]  += carry
            carry = h[i] >> 26
            h[i]  &= LimbMask
        }

        h[0]  += carry * 5
        carry = h[0] >> 26
        h[0]  &= LimbMask
        h[1]  += carry

        // Compute `h - p` and keep it only when it did not borrow, which is the
        // branch-free way to reduce the last time.
        var g: [5] u64
        g[0]  = h[0] + 5
        carry = g[0] >> 26
        g[0]  &= LimbMask
        for i in 1 to 3
        {
            g[i]  = h[i] + carry
            carry = g[i] >> 26
            g[i]  &= LimbMask
        }

        g[4] = h[4] + carry - (1 << 26)

        let borrowed = (g[4] >> 63) & 1
        let keepG    = borrowed - 1
        let keepH    = ~keepG
        for i in 5 do
            h[i] = (h[i] & keepH) | (g[i] & keepG)

        var packed: [4] u64
        packed[0] = (h[0] | (h[1] << 26)) & 0xFFFF_FFFF
        packed[1] = ((h[1] >> 6) | (h[2] << 20)) & 0xFFFF_FFFF
        packed[2] = ((h[2] >> 12) | (h[3] << 14)) & 0xFFFF_FFFF
        packed[3] = ((h[3] >> 18) | (h[4] << 8)) & 0xFFFF_FFFF

        var result: #returntype
        var sum = 0'u64
        for i in 4
        {
            sum = packed[i] + .pad[i] + (sum >> 32)
            for b in 4 do
                result[i * 4 + b] = cast(u8, ((sum >> cast(u32, (b * 8))) & 0xFF))
        }

        secureClear(h)
        secureClear(g)
        secureClear(packed)
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
        var scaled: [5] u64
        for i in 1 to 4 do
            scaled[i] = .r[i] * 5

        var h = .accumulator
        var d: [5] u64
        for block in count
        {
            let data = cast(const [*] u64, blocks + block * Poly1305BlockSize)
            let low  = Math.littleEndianToNative(data[0])
            let high = Math.littleEndianToNative(data[1])
            h[0] += low & LimbMask
            h[1] += (low >> 26) & LimbMask
            h[2] += ((low >> 52) | (high << 12)) & LimbMask
            h[3] += (high >> 14) & LimbMask
            h[4] += (high >> 40) | highBit

            d[0] = h[0] * .r[0] + h[1] * scaled[4] + h[2] * scaled[3] + h[3] * scaled[2] + h[4] * scaled[1]
            d[1] = h[0] * .r[1] + h[1] * .r[0] + h[2] * scaled[4] + h[3] * scaled[3] + h[4] * scaled[2]
            d[2] = h[0] * .r[2] + h[1] * .r[1] + h[2] * .r[0] + h[3] * scaled[4] + h[4] * scaled[3]
            d[3] = h[0] * .r[3] + h[1] * .r[2] + h[2] * .r[1] + h[3] * .r[0] + h[4] * scaled[4]
            d[4] = h[0] * .r[4] + h[1] * .r[3] + h[2] * .r[2] + h[3] * .r[1] + h[4] * .r[0]

            var carry = 0'u64
            for i in 5
            {
                d[i]  += carry
                carry = d[i] >> 26
                h[i]  = d[i] & LimbMask
            }

            h[0]  += carry * 5
            carry = h[0] >> 26
            h[0]  &= LimbMask
            h[1]  += carry
        }

        .accumulator = h
        secureClear(h)
        secureClear(d)
        secureClear(scaled)
    }
}
