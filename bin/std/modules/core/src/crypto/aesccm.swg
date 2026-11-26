#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

using Math.Simd

// AES-CCM authentication tag size in bytes for supported even tag lengths.
public const AesCcmTagMinSize = 4

// Maximum AES-CCM authentication tag size in bytes.
public const AesCcmTagMaxSize = 16

private const AesCcmParallelThreshold = 64 * 1024

private func aesCcmValidTagSize(size: u64)->bool
{
    return size >= AesCcmTagMinSize and size <= AesCcmTagMaxSize and size % 2 == 0
}

private func aesCcmMacBlock(aes: *Aes, state: *[AesBlockSize] u8, block: *[AesBlockSize] u8) fail
{
    for index in AesBlockSize
    {
        block[][index] ^= state[][index]
    }

    try aes[].encryptBlock(block[], state[])
}

private func aesCcmMacAppend(aes: *Aes, state: *[AesBlockSize] u8, block: *[AesBlockSize] u8, position: *u64, data: const [..] u8) fail
{
    var offset = 0_u64
    while offset < data.count
    {
        let count = Math.min(AesBlockSize - position[], data.count - offset)
        Swag.memcpy(&block[][position[]], data.buffer + offset, count)
        position[] += count
        offset     += count
        if position[] == AesBlockSize
        {
            try aesCcmMacBlock(aes, state, block)
            Memory.set(&block[][0], 0_u8, AesBlockSize)
            position[] = 0
        }
    }
}

private func aesCcmWriteAdLength(length: u64, header: *[10] u8)->u64
{
    if length < 0xFF00
    {
        header[][0] = Math.byteAt(cast(u32, length), 1)
        header[][1] = Math.byteAt(cast(u32, length), 0)
        return 2
    }

    if length <= Swag.U32.Max
    {
        header[][0] = 0xFF
        header[][1] = 0xFE
        for index in 4
        {
            header[][2 + index] = Math.byteAt(cast(u32, length), 3 - index)
        }

        return 6
    }

    header[][0] = 0xFF
    header[][1] = 0xFF
    for index in 8
    {
        header[][2 + index] = cast(u8, (length >> cast(u32, (7 - index) * 8)) & 0xFF)
    }

    return 10
}

private func aesCcmMacAssociatedData(aes: *Aes, state: *[AesBlockSize] u8, associatedData: const [..] u8) fail
{
    if not associatedData.count
    {
        return
    }

    var block:  [AesBlockSize] u8
    var position     = 0_u64
    var header: [10] u8
    let headerLength = aesCcmWriteAdLength(associatedData.count, &header)
    try aesCcmMacAppend(aes, state, &block, &position, Swag.makeSlice(&header[0], headerLength))
    try aesCcmMacAppend(aes, state, &block, &position, associatedData)
    if position
    {
        try aesCcmMacBlock(aes, state, &block)
        Crypto.secureClear(block)
    }

    Crypto.secureClear(header)
}

private func aesCcmMacDataHardware(aes: *Aes, state: *[AesBlockSize] u8, data: const [..] u8)
{
    let fullBlockBytes = data.count & ~15'u64
    let tailBytes = data.count - fullBlockBytes
    var chained: [1] U8x16 = [load(&state[][0])]
    for block in fullBlockBytes / AesBlockSize do
        chained[0] = aes[].encryptBlockHardware(chained[0] ^ load(data.buffer + block * AesBlockSize))

    if tailBytes
    {
        var tail: [AesBlockSize] u8
        Swag.memcpy(&tail[0], data.buffer + fullBlockBytes, tailBytes)
        chained[0] = aes[].encryptBlockHardware(chained[0] ^ load(&tail[0]))
        Crypto.secureClear(tail)
    }

    store(&state[][0], chained[0])
    Crypto.secureClear(chained)
}

private func aesCcmInitialCounter(nonce: const [..] u8)->[AesBlockSize] u8
{
    var result: #returntype
    result[0] = cast(u8, 14 - nonce.count)
    Swag.memcpy(&result[1], nonce.buffer, nonce.count)
    return result
}

private func aesCcmStartMac(aes: *Aes, nonce, associatedData: const [..] u8, plaintextSize, tagSize: u64, state: *[AesBlockSize] u8) fail
{
    let lengthBytes = 15 - nonce.count
    var block: [AesBlockSize] u8
    block[0] = cast(u8, (cast(u64, associatedData.count != 0) << 6) | (((tagSize - 2) / 2) << 3) | (lengthBytes - 1))
    Swag.memcpy(&block[1], nonce.buffer, nonce.count)
    for index in lengthBytes
    {
        block[15 - index] = cast(u8, (plaintext.count >> cast(u32, index * 8)) & 0xFF)
    }

    defer Crypto.secureClear(block)
    try aesCcmMacBlock(aes, state, &block)
    try aesCcmMacAssociatedData(aes, state, associatedData)
}

    var offset = 0_u64
    while offset < plaintext.count
    {
        var messageBlock: [AesBlockSize] u8
        let count = Math.min(plaintext.count - offset, AesBlockSize)
        Swag.memcpy(&messageBlock[0], plaintext.buffer + offset, count)
        try aesCcmMacBlock(aes, &state, &messageBlock)
        Crypto.secureClear(messageBlock)
        offset += count
    }

    var result = state
    var counter: [AesBlockSize] u8
    counter[0] = cast(u8, lengthBytes - 1)
    Swag.memcpy(&counter[1], nonce.buffer, nonce.count)
    var encryptedCounter: [AesBlockSize] u8
    try aes.encryptBlock(counter, encryptedCounter)
    for index in tagSize
    {
        result[index] ^= encryptedCounter[index]
    }

    Crypto.secureClear(state)
    Crypto.secureClear(counter)
    Crypto.secureClear(encryptedCounter)
    return result
}

private func aesCcmComputeTag(aes: *Aes, nonce: const [..] u8, associatedData, plaintext: const [..] u8, tagSize: u64)->[AesBlockSize] u8 fail
{
    var state: [AesBlockSize] u8
    defer Crypto.secureClear(state)
    try aesCcmStartMac(aes, nonce, associatedData, plaintext.count, tagSize, &state)
    if aes[].usesHardwareRounds()
    {
        aesCcmMacDataHardware(aes, &state, plaintext)
    }
    else
    {
        var offset = 0'u64
        while offset < plaintext.count
        {
            var messageBlock: [AesBlockSize] u8
            let count = Math.min(plaintext.count - offset, AesBlockSize)
            Swag.memcpy(&messageBlock[0], plaintext.buffer + offset, count)
            try aesCcmMacBlock(aes, &state, &messageBlock)
            Crypto.secureClear(messageBlock)
            offset += count
        }
    }

    var counter = aesCcmInitialCounter(nonce)
    defer Crypto.secureClear(counter)
    return try aesCcmFinishTag(aes, &counter, &state, tagSize)
}

private func aesCcmEncryptMacHardware(aes: *Aes, counterZero: [AesBlockSize] u8, source: const [..] u8, destination: [..] u8, state: *[AesBlockSize] u8)
{
    var initialCounter = counterZero
    initialCounter[15] = 1
    let prefix = cast #bit (U64x2, load(&initialCounter[0]))
    let low    = Swag.byteSwap(prefix[1])
    let blocks = source.count / AesBlockSize
    let rounds = aes[].hardwareRoundCount()
    let initialKey = aes[].roundKey(0)
    let finalKey   = aes[].roundKey(rounds)
    var chained: [1] U8x16 = [load(&state[][0])]
    for block in blocks
    {
        let offset = block * AesBlockSize
        let plaintext = load(source.buffer + offset)
        var counter = prefix
        counter[1] = Swag.byteSwap(low + block)
        var auth   = chained[0] ^ plaintext ^ initialKey
        var stream = cast #bit (U8x16, counter) ^ initialKey
        // Both operations use the same schedule and their round pipelines are independent.
        for round in 1 until rounds
        {
            let key = aes[].roundKey(round)
            auth    = Swag.vecAesEncryptRound(auth, key)
            stream  = Swag.vecAesEncryptRound(stream, key)
        }

        chained[0] = Swag.vecAesEncryptLastRound(auth, finalKey)
        store(destination.buffer + offset, plaintext ^ Swag.vecAesEncryptLastRound(stream, finalKey))
    }

    store(&state[][0], chained[0])
    Crypto.secureClear(chained)
    let fullBlockBytes = blocks * AesBlockSize
    if fullBlockBytes != source.count
    {
        // Authenticate the padded plaintext before overwriting an in-place tail.
        aesCcmMacDataHardware(aes, state, source[fullBlockBytes until])
        aesXorCounterBlocksHardware'64(aes, prefix, source, destination, blocks, 1)
    }
}

private func aesCcmCryptBlocks(aes: *Aes, nonce: const [..] u8, source: const [..] u8, destination: [..] u8, firstBlock, blockCount: u64) fail
{
    let lengthBytes = 15 - nonce.count
    var initial = aesCcmInitialCounter(nonce)
    initial[15] = 1
    // The mode has already checked the payload length against the nonce-selected counter width.
    let prefix = cast #bit (U64x2, load(&initial[0]))
    if aes[].usesHardwareRounds()
    {
        aesXorCounterBlocksHardware'64(aes, prefix, source, destination, firstBlock, blockCount)
        return
    }

    var block = aesXorCounterPairsSoftware'64(aes, prefix, source, destination, firstBlock, blockCount)
    while block < firstBlock + blockCount
    {
        var counter: [AesBlockSize] u8
        counter[0] = cast(u8, lengthBytes - 1)
        Swag.memcpy(&counter[1], nonce.buffer, nonce.count)
        let counterValue = block + 1
        for index in lengthBytes
        {
            counter[15 - index] = cast(u8, (counterValue >> cast(u32, index * 8)) & 0xFF)
        }

        var keyStream: [AesBlockSize] u8
        try aes[].encryptBlock(counter, keyStream)
        let offset = block * AesBlockSize
        let count  = Math.min(source.count - offset, AesBlockSize)
        for index in count
        {
            destination[offset + index] = source[offset + index] ^ keyStream[index]
        }

        Crypto.secureClear(counter)
        Crypto.secureClear(keyStream)
        block += 1
    }
}

private func aesCcmCrypt(aes: *Aes, nonce: const [..] u8, source: const [..] u8, destination: [..] u8) fail
{
    const BatchBlocks = 1024
    let blockCount = source.count / AesBlockSize + cast(u64, (source.count % AesBlockSize) != 0)
    if source.count < AesCcmParallelThreshold or Swag.workerCount() <= 1
    {
        try aesCcmCryptBlocks(aes, nonce, source, destination, 0, blockCount)
        return
    }

    let batchCount = blockCount / BatchBlocks + cast(u64, (blockCount % BatchBlocks) != 0)
    catch parallel for |&aes, &nonce, &source, &destination, blockCount| batch in batchCount
    {
        let firstBlock = batch * BatchBlocks
        let count      = Math.min(blockCount - firstBlock, BatchBlocks)
        try aesCcmCryptBlocks(aes, nonce, source, destination, firstBlock, count)
    }
    {
        fail Swag.err
    }
}

private func aesCcmValidate(nonce, input: const [..] u8, output: [..] u8, tag: const [..] u8) fail
{
    if nonce.count < 7 or
       nonce.count > 13 or
       not aesCcmValidTagSize(tag.count) or
       input.count != output.count
    {
        fail Errors.BadParameterError{"AES-CCM needs a 7-to-13-byte nonce, a 4-to-16-byte even tag, and matching data lengths"}
    }

    let lengthBytes = 15 - nonce.count
    if lengthBytes < 8 and input.count >= (1_u64 << cast(u32, lengthBytes * 8))
    {
        fail Errors.BadParameterError{"AES-CCM payload does not fit the nonce-selected length field"}
    }
}

// Encrypts and authenticates data with AES-CCM.
//
// Supports 16, 24, or 32-byte AES keys, 7-to-13-byte nonces, and even 4-to-16-byte tags.
// Never reuse a nonce with the same key. Ciphertext matches plaintext length; exact in-place
// operation and disjoint input/output are supported. Associated data is authenticated but not
// encrypted, and the tag must be disjoint from ciphertext.
func aesCcmEncrypt(key, nonce, associatedData, plaintext: const [..] u8, ciphertext: [..] u8, tag: [..] u8) fail
{
    try aesCcmValidate(nonce, plaintext, ciphertext, tag)
    var aes = try Aes.create(key)
    defer aes.clear()
    var computedTag: [AesBlockSize] u8
    defer Crypto.secureClear(computedTag)
    if plaintext.count >= 64 and aes.usesHardwareRounds() and
       (plaintext.count < AesCcmParallelThreshold or Swag.workerCount() <= 1)
    {
        var state: [AesBlockSize] u8
        defer Crypto.secureClear(state)
        var counter = aesCcmInitialCounter(nonce)
        defer Crypto.secureClear(counter)
        try aesCcmStartMac(&aes, nonce, associatedData, plaintext.count, tag.count, &state)
        aesCcmEncryptMacHardware(&aes, counter, plaintext, ciphertext, &state)
        computedTag = try aesCcmFinishTag(&aes, &counter, &state, tag.count)
    }
    else
    {
        computedTag = try aesCcmComputeTag(&aes, nonce, associatedData, plaintext, tag.count)
        try aesCcmCrypt(&aes, nonce, plaintext, ciphertext)
    }
    Swag.memcpy(tag.buffer, &computedTag[0], tag.count)
}

// Authenticates and decrypts AES-CCM ciphertext, leaving output unchanged on tag failure.
//
// `key`, `nonce`, `associatedData`, and `tag` must match encryption. Plaintext output length must
// equal ciphertext length; exact in-place operation and disjoint slices are supported.
func aesCcmDecrypt(key, nonce, associatedData, ciphertext, tag: const [..] u8, plaintext: [..] u8) fail
{
    try aesCcmValidate(nonce, ciphertext, plaintext, tag)
    var aes = try Aes.create(key)
    defer aes.clear()
    var temporary: Array!{u8}
    temporary.resize(ciphertext.count)
    defer Crypto.secureClear(temporary.toSlice())
    try aesCcmCrypt(&aes, nonce, ciphertext, temporary.toSlice())
    var computedTag = try aesCcmComputeTag(&aes, nonce, associatedData, temporary.toSlice(), tag.count)
    defer Crypto.secureClear(computedTag)
    if not Crypto.constantTimeEqual(computedTag[until tag.count], tag)
    {
        fail Errors.BadParameterError{"AES-CCM authentication failed"}
    }

    if plaintext.count
    {
        Swag.memcpy(plaintext.buffer, temporary.toSlice().buffer, plaintext.count)
    }
}
