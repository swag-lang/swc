#global public
#global namespace Crypto

// Stores an HMAC-SHA-512 result as 64 bytes in network order.
alias HmacSha512Digest = [64] u8

// Stores an HMAC-SHA-384 result as 48 bytes in network order.
alias HmacSha384Digest = [48] u8

#[Swag.Inline]
private func(Words: u64) sha512DigestBytes(digest: [Words] u64)->[Words * #sizeof(u64)] u8
{
    var result: #returntype
    let destination = cast([*] u64, result.buffer)
    for pair in Words / 2
    {
        let index = pair * 2
        Math.Simd.store(destination + index, Math.nativeToBigEndian(Math.Simd.load(digest.buffer + index)))
    }

    return result
}

#[Swag.Inline]
private func fillSha512Pads(key: const [*] u8, inner, outer: [*] u8)
{
    let innerMask = Math.Simd.splat(0x36'u8)
    let outerMask = Math.Simd.splat(0x5C'u8)
    const Width = #sizeof(Math.Simd.U8x16)
    for group in Hash.Sha512BlockSize / Width
    {
        let offset = group * Width
        let value  = Math.Simd.load(key + offset)
        Math.Simd.store(inner + offset, value ^ innerMask)
        Math.Simd.store(outer + offset, value ^ outerMask)
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
        .clear()
        var normalized: [Hash.Sha512BlockSize] u8
        if key.count > Hash.Sha512BlockSize
        {
            var hashed = sha512DigestBytes(Hash.Sha512.compute(key))
            Swag.memcpy(&normalized[0], &hashed[0], #sizeof(hashed))
            secureClear(hashed)
        }
        elif key.count
        {
            Swag.memcpy(&normalized[0], key.buffer, key.count)
        }

        var innerPad: [Hash.Sha512BlockSize] u8
        var outerPad: [Hash.Sha512BlockSize] u8
        fillSha512Pads(normalized.buffer, innerPad.buffer, outerPad.buffer)

        .inner.reset()
        .outer.reset()
        .inner.update(innerPad)
        .outer.update(outerPad)
        .initialized = true
        secureClear(normalized)
        secureClear(innerPad)
        secureClear(outerPad)
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
        var innerHash = sha512DigestBytes(.inner.finalize())
        .outer.update(innerHash)
        let result = sha512DigestBytes(.outer.finalize())
        secureClear(innerHash)
        .clear()
        return result
    }

    // Clears all keyed state held by this value.
    mtd clear()
    {
        .inner.clear()
        .outer.clear()
        .initialized = false
    }

    // Computes HMAC-SHA-512 for `data` in one operation.
    func compute(key, data: const [..] u8)->HmacSha512Digest
    {
        var hmac = HmacSha512.create(key)
        hmac.update(data)
        return hmac.finalize()
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop() => .clear()
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
        .clear()
        var normalized: [Hash.Sha512BlockSize] u8
        if key.count > Hash.Sha512BlockSize
        {
            var hashed = sha512DigestBytes(Hash.Sha384.compute(key))
            Swag.memcpy(&normalized[0], &hashed[0], #sizeof(hashed))
            secureClear(hashed)
        }
        elif key.count
        {
            Swag.memcpy(&normalized[0], key.buffer, key.count)
        }

        var innerPad: [Hash.Sha512BlockSize] u8
        var outerPad: [Hash.Sha512BlockSize] u8
        fillSha512Pads(normalized.buffer, innerPad.buffer, outerPad.buffer)

        .inner.reset()
        .outer.reset()
        .inner.update(innerPad)
        .outer.update(outerPad)
        .initialized = true
        secureClear(normalized)
        secureClear(innerPad)
        secureClear(outerPad)
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
        var innerHash = sha512DigestBytes(.inner.finalize())
        .outer.update(innerHash)
        let result = sha512DigestBytes(.outer.finalize())
        secureClear(innerHash)
        .clear()
        return result
    }

    // Clears all keyed state held by this value.
    mtd clear()
    {
        .inner.clear()
        .outer.clear()
        .initialized = false
    }

    // Computes HMAC-SHA-384 for `data` in one operation.
    func compute(key, data: const [..] u8)->HmacSha384Digest
    {
        var hmac = HmacSha384.create(key)
        hmac.update(data)
        return hmac.finalize()
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop() => .clear()
}
