#global public
#global namespace Crypto

// AES-CMAC tag size in bytes.
public const AesCmacTagSize = 16

// Stores an AES-CMAC result as a full 128-bit tag.
alias AesCmacTag = [AesCmacTagSize] u8

private func aesCmacDouble(value: *[AesBlockSize] u8)
{
    var carry = 0'u8
    for index in AesBlockSize
    {
        let byteIndex = AesBlockSize - 1 - index
        let next      = value[][byteIndex] >> 7
        value[][byteIndex] = cast(u8, (value[][byteIndex] << 1) | carry)
        carry = next
    }

    value[][AesBlockSize - 1] ^= 0x87'u8 & cast(u8, 0'u8 - carry)
}

// Computes AES-CMAC incrementally using an opaque key schedule and chaining state.
#[Swag.NoCopy, Swag.Opaque]
struct AesCmac
{
    aes:         Aes
    subKey1:     [AesBlockSize] u8
    subKey2:     [AesBlockSize] u8
    state:       [AesBlockSize] u8
    buffer:      [AesBlockSize] u8
    bufferCount: u64
    initialized: bool
}

impl AesCmac
{
    // Creates an initialized AES-CMAC sequence for a 16, 24, or 32-byte AES key.
    func create(key: const [..] u8)->AesCmac fail
    {
        var result: #returntype
        try result.reset(key)
        return result
    }

    // Replaces previous state and starts a new sequence for `key`.
    mtd reset(key: const [..] u8) fail
    {
        .clear()
        try .aes.reset(key)

        var zero:  [AesBlockSize] u8
        var value: [AesBlockSize] u8
        try .aes.encryptBlock(zero, value)
        aesCmacDouble(&value)
        .subKey1 = value
        aesCmacDouble(&value)
        .subKey2     = value
        .initialized = true
        Crypto.secureClear(value)
    }

    // Includes `data` in the running message authentication code.
    mtd update(data: const [..] u8) fail
    {
        Swag.assert(.initialized, "AES-CMAC needs an initialized sequence")
        var offset = 0'u64
        while offset < data.count
        {
            if .bufferCount == AesBlockSize do
                try .processBufferedBlock()
            let count = Math.min(AesBlockSize - .bufferCount, data.count - offset)
            Swag.memcpy(&.buffer[.bufferCount], data.buffer + offset, count)
            .bufferCount += count
            offset       += count
        }
    }

    // Finalizes the message, returns its 128-bit tag, and clears the keyed state.
    //
    // Call [[reset]] before reusing this value.
    mtd finalize()->AesCmacTag fail
    {
        Swag.assert(.initialized, "AES-CMAC needs an initialized sequence")
        var finalBlock: [AesBlockSize] u8
        if .bufferCount == AesBlockSize
        {
            for index in AesBlockSize do
                finalBlock[index] = .buffer[index] ^ .subKey1[index]
        }
        else
        {
            if .bufferCount do
                Swag.memcpy(&finalBlock[0], &.buffer[0], .bufferCount)
            finalBlock[.bufferCount] = 0x80
            for index in AesBlockSize do
                finalBlock[index] ^= .subKey2[index]
        }

        for index in AesBlockSize do
            finalBlock[index] ^= .state[index]
        var result: #returntype
        try .aes.encryptBlock(finalBlock, result)
        Crypto.secureClear(finalBlock)
        .clear()
        return result
    }

    // Clears the expanded key, subkeys, and buffered message state.
    mtd clear()
    {
        .aes.clear()
        Crypto.secureClear(.subKey1)
        Crypto.secureClear(.subKey2)
        Crypto.secureClear(.state)
        Crypto.secureClear(.buffer)
        .bufferCount = 0
        .initialized = false
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }

    // Computes AES-CMAC for `data` in one operation.
    func compute(key, data: const [..] u8)->AesCmacTag fail
    {
        var cmac = try AesCmac.create(key)
        try cmac.update(data)
        return try cmac.finalize()
    }

    private mtd processBufferedBlock() fail
    {
        var block: [AesBlockSize] u8
        for index in AesBlockSize do
            block[index] = .state[index] ^ .buffer[index]
        try .aes.encryptBlock(block, .state)
        Crypto.secureClear(block)
        Crypto.secureClear(.buffer)
        .bufferCount = 0
    }
}
