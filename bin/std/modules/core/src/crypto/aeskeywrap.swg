#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// AES-KW and AES-KWP integrity check size in bytes.
public const AesKeyWrapIntegritySize = 8

private const AesKeyWrapIv: [AesKeyWrapIntegritySize] u8 = [
    0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6]

private const AesKeyWrapPaddedIvPrefix: [4] u8 = [0xA6, 0x59, 0x59, 0xA6]

private func aesKeyWrapWriteRound(value: u64, destination: [*] u8)
{
    for index in 8 do
        destination[index] = cast(u8, (value >> cast(u32, (7 - index) * 8)) & 0xFF)
}

private func aesKeyWrapWriteLength(value: u32, destination: [*] u8)
{
    for index in 4 do
        destination[index] = Math.byteAt(value, 3 - index)
}

private func aesKeyWrapReadLength(source: const [*] u8)->u32
{
    var value = 0'u32
    for index in 4 do
        value = (value << 8) | cast(u32, source[index])
    return value
}

private func aesKeyWrapWrapCore(aes: *Aes, initialA: [AesKeyWrapIntegritySize] u8, input: const [..] u8, output: [..] u8) fail
{
    let blockCount = input.count / 8
    var a = initialA
    Swag.memcpy(output.buffer + 8, input.buffer, input.count)
    Swag.memcpy(output.buffer, &a[0], 8)
    var round = 0'u64
    while round < 6
    {
        var index = 0'u64
        while index < blockCount
        {
            var block:     [16] u8
            var encrypted: [16] u8
            Swag.memcpy(&block[0], &a[0], 8)
            Swag.memcpy(&block[8], output.buffer + 8 + index * 8, 8)
            try aes[].encryptBlock(block, encrypted)
            let roundNumber = blockCount * round + index + 1
            aesKeyWrapWriteRound(roundNumber, &block[0])
            for byte in 8 do
                a[byte] = encrypted[byte] ^ block[byte]
            Swag.memcpy(output.buffer + 8 + index * 8, &encrypted[8], 8)
            Crypto.secureClear(block)
            Crypto.secureClear(encrypted)
            index += 1
        }

        round += 1
    }

    Swag.memcpy(output.buffer, &a[0], 8)
    Crypto.secureClear(a)
}

private func aesKeyWrapUnwrapCore(aes: *Aes, input: const [..] u8, a: *[AesKeyWrapIntegritySize] u8, output: [..] u8) fail
{
    let blockCount = output.count / 8
    Swag.memcpy(&a[][0], input.buffer, 8)
    Swag.memcpy(output.buffer, input.buffer + 8, output.count)
    var round = 6'u64
    while round > 0
    {
        round -= 1
        var index = blockCount
        while index > 0
        {
            index -= 1
            var block:     [16] u8
            var decrypted: [16] u8
            let roundNumber = blockCount * round + index + 1
            for byte in 8 do
                block[byte] = a[][byte]
            aesKeyWrapWriteRound(roundNumber, &block[0])
            for byte in 8 do
                block[byte] ^= a[][byte]
            Swag.memcpy(&block[8], output.buffer + index * 8, 8)
            try aes[].decryptBlock(block, decrypted)
            Swag.memcpy(&a[][0], &decrypted[0], 8)
            Swag.memcpy(output.buffer + index * 8, &decrypted[8], 8)
            Crypto.secureClear(block)
            Crypto.secureClear(decrypted)
        }
    }
}

// Wraps key material with AES-KW (RFC 3394).
//
// `wrappingKey` must be a 16, 24, or 32-byte AES key. `keyData` must contain at least two
// 64-bit blocks, and `wrapped` must be exactly eight bytes longer. The output is authenticated
// by the standard 64-bit integrity value; input and output must be disjoint.
func aesKeyWrap(wrappingKey, keyData: const [..] u8, wrapped: [..] u8) fail
{
    if keyData.count < 16 or
       keyData.count % 8 or
       keyData.count > Swag.U64.Max - AesKeyWrapIntegritySize or
       wrapped.count != keyData.count + AesKeyWrapIntegritySize do
        fail Errors.BadParameterError{"AES-KW needs at least 16 bytes of 64-bit aligned key data and an output eight bytes longer"}

    var aes = try Aes.create(wrappingKey)
    defer aes.clear()
    try aesKeyWrapWrapCore(&aes, AesKeyWrapIv, keyData, wrapped)
}

// Unwraps key material with AES-KW (RFC 3394), failing on an invalid integrity value.
//
// `wrapped` must contain at least 24 bytes and be 64-bit aligned. `keyData` must be exactly
// eight bytes shorter; it is left untouched when integrity verification fails.
func aesKeyUnwrap(wrappingKey, wrapped: const [..] u8, keyData: [..] u8) fail
{
    if wrapped.count < 24 or wrapped.count % 8 or keyData.count != wrapped.count - 8 do
        fail Errors.BadParameterError{"AES-KW needs at least 24 bytes of wrapped data and an output eight bytes shorter"}

    var aes = try Aes.create(wrappingKey)
    defer aes.clear()
    var temporary: Array'u8
    temporary.resize(keyData.count)
    defer Crypto.secureClear(temporary.toSlice())
    var a: [AesKeyWrapIntegritySize] u8
    try aesKeyWrapUnwrapCore(&aes, wrapped, &a, temporary.toSlice())
    let valid = Crypto.constantTimeEqual(a, AesKeyWrapIv)
    Crypto.secureClear(a)
    if not valid
    {
        fail Errors.BadParameterError{"AES-KW integrity check failed"}
    }

    Swag.memcpy(keyData.buffer, &temporary[0], keyData.count)
}

// Wraps 1 to 2^32-1 bytes with AES-KWP (RFC 5649), adding zero padding and an encoded length.
//
// `wrapped` must have the RFC 5649 output length: 16 bytes for key data up to eight bytes,
// otherwise the next multiple of eight bytes plus the eight-byte integrity value. Input and
// output must be disjoint.
func aesKeyWrapWithPadding(wrappingKey, keyData: const [..] u8, wrapped: [..] u8) fail
{
    if keyData.count == 0 or keyData.count > Swag.U32.Max do
        fail Errors.BadParameterError{"AES-KWP key data must contain between 1 and 2^32-1 bytes"}
    let paddedLength  = (keyData.count + 7) & ~7'u64
    let wrappedLength = Math.max(16, paddedLength + 8)
    if wrapped.count != wrappedLength do
        fail Errors.BadParameterError{"AES-KWP output has the wrong length"}

    var aes = try Aes.create(wrappingKey)
    defer aes.clear()
    var padded: Array'u8
    padded.resize(paddedLength)
    defer Crypto.secureClear(padded.toSlice())
    Swag.memcpy(&padded[0], keyData.buffer, keyData.count)
    if paddedLength > keyData.count do
        Memory.set(padded.toSlice().buffer + keyData.count, 0'u8, paddedLength - keyData.count)
    var initialA: [AesKeyWrapIntegritySize] u8
    Swag.memcpy(&initialA[0], &AesKeyWrapPaddedIvPrefix[0], 4)
    aesKeyWrapWriteLength(cast(u32, keyData.count), &initialA[4])

    if paddedLength == 8
    {
        var block: [16] u8
        Swag.memcpy(&block[0], &initialA[0], 8)
        Swag.memcpy(&block[8], padded.toSlice().buffer, 8)
        try aes.encryptBlock(block, wrapped)
        Crypto.secureClear(block)
    }
    else
    {
        try aesKeyWrapWrapCore(&aes, initialA, padded.toSlice(), wrapped)
    }

    Crypto.secureClear(initialA)
}

// Unwraps AES-KWP data, checking the encoded length and every padding byte before writing output.
//
// `keyData` needs capacity for at least `wrapped.count - 8` bytes. Returns the actual key-data
// length and leaves the destination untouched if the integrity value, length, or padding is invalid.
func aesKeyUnwrapWithPadding(wrappingKey, wrapped: const [..] u8, keyData: [..] u8)->u64 fail
{
    if wrapped.count < 16 or wrapped.count % 8 or keyData.count < wrapped.count - 8 do
        fail Errors.BadParameterError{"AES-KWP needs at least 16 bytes of wrapped data and sufficient output capacity"}

    var aes = try Aes.create(wrappingKey)
    defer aes.clear()
    let paddedLength = wrapped.count - 8
    var temporary: Array'u8
    temporary.resize(paddedLength)
    defer Crypto.secureClear(temporary.toSlice())
    var a: [AesKeyWrapIntegritySize] u8
    if wrapped.count == 16
    {
        var block: [16] u8
        try aes.decryptBlock(wrapped, block)
        Swag.memcpy(&a[0], &block[0], 8)
        Swag.memcpy(&temporary[0], &block[8], 8)
        Crypto.secureClear(block)
    }
    else
    {
        try aesKeyWrapUnwrapCore(&aes, wrapped, &a, temporary.toSlice())
    }

    var invalid = 0'u8
    for index in 4 do
        invalid |= a[index] ^ AesKeyWrapPaddedIvPrefix[index]
    let messageLength = aesKeyWrapReadLength(&a[4])
    let validLength   = messageLength > paddedLength - 8 and messageLength <= paddedLength
    if not validLength do
        invalid |= 1
    let safeLength   = Math.min(cast(u64, messageLength), paddedLength)
    var paddingIndex = safeLength
    while paddingIndex < paddedLength
    {
        invalid      |= temporary[paddingIndex]
        paddingIndex += 1
    }

    Crypto.secureClear(a)
    if invalid
    {
        fail Errors.BadParameterError{"AES-KWP integrity, length, or padding check failed"}
    }

    Swag.memcpy(keyData.buffer, &temporary[0], messageLength)
    return messageLength
}
