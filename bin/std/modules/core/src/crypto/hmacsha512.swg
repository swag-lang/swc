#global public
#global namespace Crypto

// Stores an HMAC-SHA-512 result as 64 bytes in network order.
alias HmacSha512Digest = [64] u8

// Stores an HMAC-SHA-384 result as 48 bytes in network order.
alias HmacSha384Digest = [48] u8

#[Swag.Inline]
internal func(Words: u64) writeSha512HmacDigest(digest: const [*] u64, output: [*] u8)
{
    let destination = cast([*] u64, output)
    for pair in Words / 2
    {
        let index = pair * 2
        Math.Simd.store(destination + index, Math.nativeToBigEndian(Math.Simd.load(digest + index)))
    }

}

#[Swag.Inline]
private func(Words: u64) sha512DigestBytes(digest: [Words] u64)->[Words * #sizeof(u64)] u8
{
    var result: #returntype
    writeSha512HmacDigest'Words(digest.buffer, result.buffer)
    return result
}

#[Swag.Inline]
private func(Mask: u8) xorSha512HmacPad(pad: [*] u8)
{
    let mask = Math.Simd.splat(Mask)
    const Width = #sizeof(Math.Simd.U8x16)
    for group in Hash.Sha512BlockSize / Width
    {
        let block = pad + group * Width
        Math.Simd.store(block, Math.Simd.load(block) ^ mask)
    }
}

// Computes HMAC-SHA-512 incrementally while keeping its keyed state opaque.
#[Swag.NoCopy, Swag.Opaque]
public struct HmacSha512
{
    inner:       Hash.Sha512
    outer:       Hash.Sha512
    initialized: bool
}

public impl HmacSha512
{
    // Creates an initialized HMAC-SHA-512 sequence for `key`.
    func create(key: const [..] u8)->HmacSha512
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

        var pad: [Hash.Sha512BlockSize] u8
        if key.count > Hash.Sha512BlockSize
        {
            var hashed = sha512DigestBytes(Hash.Sha512.compute(key))
            Swag.memcpy(&pad[0], &hashed[0], #sizeof(hashed))
            secureClear(hashed)
        }
        else if key.count
        {
            Swag.memcpy(&pad[0], key.buffer, key.count)
        }

        .inner.reset()
        xorSha512HmacPad'0x36(pad.buffer)
        .inner.update(pad)

        .outer.reset()

        // Convert the inner pad into the outer pad in the same buffer.
        xorSha512HmacPad'(0x36 ^ 0x5C)(pad.buffer)
        .outer.update(pad)
        .initialized = true
        secureClear(pad)
    }

    // Includes `data` in the running authentication code.
    mtd update(data: const [..] u8)
    {
        Swag.assert(.initialized, "HMAC-SHA-512 needs an initialized sequence")
        .inner.update(data)
    }

    // Finalizes the sequence, returns its authentication code, and clears the keyed state.
    mtd finalize()->HmacSha512Digest
    {
        Swag.assert(.initialized, "HMAC-SHA-512 needs an initialized sequence")
        let innerDigest = .inner.finishHmacInner()
        let outerDigest = .outer.finishHmacOuter(innerDigest)
        var result: #returntype
        writeSha512HmacDigest'8(outerDigest, result.buffer)
        .clear()
        return result
    }

    // Clears all keyed state held by this value.
    mtd clear()
    {
        secureClear(Swag.makeSlice(cast([*] u8, me), #sizeof(HmacSha512)))
    }

    // Computes HMAC-SHA-512 for `data` in one operation.
    func compute(key, data: const [..] u8)->HmacSha512Digest
    {
        var hmac = HmacSha512.create(key)
        hmac.update(data)
        return hmac.finalize()
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        if .initialized do
            .clear()
    }
}

// Computes HMAC-SHA-384 incrementally while keeping its keyed state opaque.
#[Swag.NoCopy, Swag.Opaque]
public struct HmacSha384
{
    inner:       Hash.Sha384
    outer:       Hash.Sha384
    initialized: bool
}

public impl HmacSha384
{
    // Creates an initialized HMAC-SHA-384 sequence for `key`.
    func create(key: const [..] u8)->HmacSha384
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

        var pad: [Hash.Sha512BlockSize] u8
        if key.count > Hash.Sha512BlockSize
        {
            var hashed = sha512DigestBytes(Hash.Sha384.compute(key))
            Swag.memcpy(&pad[0], &hashed[0], #sizeof(hashed))
            secureClear(hashed)
        }
        else if key.count
        {
            Swag.memcpy(&pad[0], key.buffer, key.count)
        }

        .inner.reset()
        xorSha512HmacPad'0x36(pad.buffer)
        .inner.update(pad)

        .outer.reset()

        // Convert the inner pad into the outer pad in the same buffer.
        xorSha512HmacPad'(0x36 ^ 0x5C)(pad.buffer)
        .outer.update(pad)
        .initialized = true
        secureClear(pad)
    }

    // Includes `data` in the running authentication code.
    mtd update(data: const [..] u8)
    {
        Swag.assert(.initialized, "HMAC-SHA-384 needs an initialized sequence")
        .inner.update(data)
    }

    // Finalizes the sequence, returns its authentication code, and clears the keyed state.
    mtd finalize()->HmacSha384Digest
    {
        Swag.assert(.initialized, "HMAC-SHA-384 needs an initialized sequence")
        let innerDigest = .inner.finishHmacInner()
        let outerDigest = .outer.finishHmacOuter(innerDigest)
        var result: #returntype
        writeSha512HmacDigest'6(outerDigest, result.buffer)
        .clear()
        return result
    }

    // Clears all keyed state held by this value.
    mtd clear()
    {
        secureClear(Swag.makeSlice(cast([*] u8, me), #sizeof(HmacSha384)))
    }

    // Computes HMAC-SHA-384 for `data` in one operation.
    func compute(key, data: const [..] u8)->HmacSha384Digest
    {
        var hmac = HmacSha384.create(key)
        hmac.update(data)
        return hmac.finalize()
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        if .initialized do
            .clear()
    }
}
