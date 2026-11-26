#global public
#global namespace Crypto

// Stores an HMAC-SHA-256 result as 32 bytes in network order.
alias HmacSha256Digest = [32] u8

// Computes HMAC-SHA-256 incrementally while keeping its keyed state opaque.
#[Swag.NoCopy, Swag.Opaque]
struct HmacSha256
{
    inner:       Hash.Sha256
    outer:       Hash.Sha256
    initialized: bool
}

#[Swag.Inline]
internal func(Words: u64) writeSha2HmacDigest(digest: const [*] u32, output: [*] u8)
{
    let destination = cast([*] u32, output)
    Math.Simd.store(destination, Math.nativeToBigEndian(Math.Simd.load(digest)))
    #static if Words == 8 do
        Math.Simd.store(destination + 4, Math.nativeToBigEndian(Math.Simd.load(digest + 4)))
    else
    {
        for index in 4 until Words do
            destination[index] = Math.nativeToBigEndian(digest[index])
    }
}

#[Swag.Inline]
internal func(Words: u64) sha2HmacDigestBytes(digest: [Words] u32)->[Words * #sizeof(u32)] u8
{
    var result: #returntype
    writeSha2HmacDigest'Words(digest.buffer, result.buffer)
    return result
}

#[Swag.Inline]
internal func(Mask: u8) xorSha2HmacPad(pad: [*] u8)
{
    let mask = Math.Simd.splat(Mask)
    const Width = #sizeof(Math.Simd.U8x16)
    for group in 64 / Width
    {
        let block = pad + group * Width
        Math.Simd.store(block, Math.Simd.load(block) ^ mask)
    }
}

impl HmacSha256
{
    // Creates an initialized HMAC-SHA-256 sequence for `key`.
    func create(key: const [..] u8)->HmacSha256
    {
        var result: #returntype
        result.reset(key)
        return result
    }

    // Replaces any previous keyed state and starts a new sequence for `key`.
    mtd reset(key: const [..] u8)
    {
        if .initialized do
            .clear()

        var pad: [64] u8
        if key.count > 64
        {
            var hashed = sha2HmacDigestBytes'8(Hash.Sha256.compute(key))
            Swag.memcpy(&pad[0], &hashed[0], #sizeof(hashed))
            secureClear(hashed)
        }
        else if key.count
        {
            Swag.memcpy(&pad[0], key.buffer, key.count)
        }

        .inner.reset()
        xorSha2HmacPad'0x36(pad.buffer)
        .inner.update(pad)

        .outer.reset()

        // Convert the inner pad into the outer pad in the same buffer.
        xorSha2HmacPad'(0x36 ^ 0x5C)(pad.buffer)
        .outer.update(pad)
        .initialized = true

        secureClear(pad)
    }

    // Includes `data` in the running authentication code.
    mtd update(data: const [..] u8)
    {
        Swag.assert(.initialized, "HMAC-SHA-256 needs an initialized sequence")
        .inner.update(data)
    }

    // Finalizes the sequence, returns its authentication code, and clears the keyed state.
    //
    // Call [[reset]] before reusing this value.
    mtd finalize()->HmacSha256Digest
    {
        Swag.assert(.initialized, "HMAC-SHA-256 needs an initialized sequence")
        let innerDigest = .inner.finishHmacInner()
        let outerDigest = .outer.finishHmacOuter'8(innerDigest)
        var result: #returntype
        writeSha2HmacDigest'8(outerDigest, result.buffer)
        .clear()
        return result
    }

    // Clears all keyed state held by this value.
    mtd clear()
    {
        secureClear(Swag.makeSlice(cast([*] u8, me), #sizeof(HmacSha256)))
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        if .initialized do
            .clear()
    }

    // Computes HMAC-SHA-256 for `data` in one operation.
    func compute(key, data: const [..] u8)->HmacSha256Digest
    {
        var hmac = HmacSha256.create(key)
        hmac.update(data)
        return hmac.finalize()
    }
}
