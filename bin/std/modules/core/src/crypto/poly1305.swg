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
    return cast(u64) data[0] | (cast(u64) data[1] << 8) |
           (cast(u64) data[2] << 16) | (cast(u64) data[3] << 24)
}

// Authenticates a message under a one-time key, following RFC 8439.
//
// A Poly1305 key authenticates exactly one message. Reusing it across two
// messages lets an observer recover the key material and forge tags, which is
// why [[Crypto.chacha20Poly1305Seal]] derives a fresh one from each nonce.
#[Swag.NoCopy]
#[Swag.Opaque]
public struct Poly1305
{
    internal
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
        var result: retval
        try result.reset(key)
        return result
    }

    // Replaces any previous state and starts a new sequence for `key`.
    mtd reset(key: const [..] u8) fail
    {
        if @countof(key) != Poly1305KeySize do
            fail Errors.BadParameterError{"Poly1305 needs a 32-byte key"}

        .clear()

        // The first half of the key is clamped: the masks are what keep every
        // partial product inside the range the limb arithmetic below assumes.
        let t0 = load32Le(@dataof(key))
        let t1 = load32Le(@dataof(key) + 4)
        let t2 = load32Le(@dataof(key) + 8)
        let t3 = load32Le(@dataof(key) + 12)
        .r[0] = t0 & 0x3FF_FFFF
        .r[1] = ((t0 >> 26) | (t1 << 6)) & 0x3FF_FF03
        .r[2] = ((t1 >> 20) | (t2 << 12)) & 0x3FF_C0FF
        .r[3] = ((t2 >> 14) | (t3 << 18)) & 0x3F0_3FFF
        .r[4] = (t3 >> 8) & 0x00F_FFFF

        // The second half is added once, at finalization.
        for [i] in 4 do
            .pad[i] = load32Le(@dataof(key) + Poly1305BlockSize + i * 4)
        .initialized = true
    }

    // Includes `data` in the running authentication code.
    mtd update(data: const [..] u8)
    {
        Debug.assert(.initialized, "Poly1305 needs an initialized sequence")

        var offset = 0'u64
        while offset < @countof(data)
        {
            let count = Math.min(@countof(data) - offset, Poly1305BlockSize - .bufferCount)
            @memcpy(&.buffer[.bufferCount], @dataof(data) + offset, count)
            .bufferCount += count
            offset       += count
            if .bufferCount == Poly1305BlockSize
            {
                .absorb(.buffer, 1 << 24)
                .bufferCount = 0
            }
        }
    }

    // Finalizes the sequence, returns its authentication tag, and clears the
    // keyed state. Call [[Core.Crypto.Poly1305.reset]] before reusing this value.
    mtd finalize()->Poly1305Tag
    {
        Debug.assert(.initialized, "Poly1305 needs an initialized sequence")

        // A partial block carries its terminator inside the block itself, which
        // is what separates a short message from a padded longer one.
        if .bufferCount
        {
            .buffer[.bufferCount] = 1
            @memset(&.buffer[.bufferCount + 1], 0, Poly1305BlockSize - .bufferCount - 1)
            .absorb(.buffer, 0)
            .bufferCount = 0
        }

        var h     = .accumulator
        var carry = h[1] >> 26
        h[1] &= LimbMask
        for [i] in 2 to 4
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
        for [i] in 1 to 3
        {
            g[i]  = h[i] + carry
            carry = g[i] >> 26
            g[i]  &= LimbMask
        }

        g[4] = h[4] + carry - (1 << 26)

        let borrowed = (g[4] >> 63) & 1
        let keepG    = borrowed - 1
        let keepH    = ~keepG
        for [i] in 5 do
            h[i] = (h[i] & keepH) | (g[i] & keepG)

        var packed: [4] u64
        packed[0] = (h[0] | (h[1] << 26)) & 0xFFFF_FFFF
        packed[1] = ((h[1] >> 6) | (h[2] << 20)) & 0xFFFF_FFFF
        packed[2] = ((h[2] >> 12) | (h[3] << 14)) & 0xFFFF_FFFF
        packed[3] = ((h[3] >> 18) | (h[4] << 8)) & 0xFFFF_FFFF

        var result: retval
        var sum = 0'u64
        for [i] in 4
        {
            sum = packed[i] + .pad[i] + (sum >> 32)
            for [b] in 4 do
                result[i * 4 + b] = cast(u8) ((sum >> cast(u32) (b * 8)) & 0xFF)
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
        secureClear(.r)
        secureClear(.pad)
        secureClear(.accumulator)
        secureClear(.buffer)
        .bufferCount = 0
        .initialized = false
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }

    // Computes the Poly1305 tag of `data` under `key` in one operation.
    func compute(key, data: const [..] u8)->Poly1305Tag fail
    {
        var mac = try Poly1305.create(key)
        mac.update(data)
        return mac.finalize()
    }

    // Adds one 16-byte block to the accumulator and multiplies by `r` modulo
    // 2^130 - 5. `terminator` carries the implicit high bit of a full block.
    private mtd absorb(block: const [..] u8, terminator: u64)
    {
        let t0 = load32Le(@dataof(block))
        let t1 = load32Le(@dataof(block) + 4)
        let t2 = load32Le(@dataof(block) + 8)
        let t3 = load32Le(@dataof(block) + 12)

        var h = .accumulator
        h[0] += t0 & 0x3FF_FFFF
        h[1] += ((t0 >> 26) | (t1 << 6)) & 0x3FF_FFFF
        h[2] += ((t1 >> 20) | (t2 << 12)) & 0x3FF_FFFF
        h[3] += ((t2 >> 14) | (t3 << 18)) & 0x3FF_FFFF
        h[4] += (t3 >> 8) | terminator

        // Reducing modulo 2^130 - 5 folds the overflow back with a factor of
        // five, so the wrapped limbs are scaled instead of discarded.
        var scaled: [5] u64
        for [i] in 1 to 4 do
            scaled[i] = .r[i] * 5

        var d: [5] u64
        d[0] = h[0] * .r[0] + h[1] * scaled[4] + h[2] * scaled[3] + h[3] * scaled[2] + h[4] * scaled[1]
        d[1] = h[0] * .r[1] + h[1] * .r[0] + h[2] * scaled[4] + h[3] * scaled[3] + h[4] * scaled[2]
        d[2] = h[0] * .r[2] + h[1] * .r[1] + h[2] * .r[0] + h[3] * scaled[4] + h[4] * scaled[3]
        d[3] = h[0] * .r[3] + h[1] * .r[2] + h[2] * .r[1] + h[3] * .r[0] + h[4] * scaled[4]
        d[4] = h[0] * .r[4] + h[1] * .r[3] + h[2] * .r[2] + h[3] * .r[1] + h[4] * .r[0]

        var carry = 0'u64
        for [i] in 5
        {
            d[i]            += carry
            carry           = d[i] >> 26
            .accumulator[i] = d[i] & LimbMask
        }

        .accumulator[0] += carry * 5
        carry           = .accumulator[0] >> 26
        .accumulator[0] &= LimbMask
        .accumulator[1] += carry

        secureClear(h)
        secureClear(d)
        secureClear(scaled)
    }
}
