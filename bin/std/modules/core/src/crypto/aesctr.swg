#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

using Math.Simd

// AES-CTR counter block size in bytes.
public const AesCtrCounterSize = 16

private func aesCtrAddCounter(counter: *[AesCtrCounterSize] u8, amount: u64)->bool
{
    var carry = amount
    for index in AesCtrCounterSize
    {
        let byteIndex = AesCtrCounterSize - 1 - index
        let sum       = cast(u64, counter[][byteIndex]) + (carry & 0xFF)
        counter[][byteIndex] = cast(u8, sum)
        carry = (carry >> 8) + (sum >> 8)
    }

    return carry == 0
}

// The mode validates its full counter range before selecting the counter width.
internal func(CounterBits: u32) aesXorCounterBlocksHardware(aes: *Aes, prefix: U64x2, source: const [..] u8, destination: [..] u8, firstBlock, blockCount: u64)
{
    #[Swag.Inline]
    func counter(initial: U64x2, low: u64, index: u64)->U8x16
    {
        #static if CounterBits == 32
        {
            discard low
            var words = cast #bit (U32x4, initial)
            // GCM reserves counter one for its tag mask.
            words[3] = Swag.byteSwap(cast(u32, index + 2))
            return cast #bit (U8x16, words)
        }
        else
        {
            let next  = low + index
            var words = initial
            words[1] = Swag.byteSwap(next)
            #static if CounterBits == 128
            {
                let high = Swag.byteSwap(initial[0])
                words[0] = Swag.byteSwap(high + cast(u64, next < low))
            }

            return cast #bit (U8x16, words)
        }
    }

    let low              = Swag.byteSwap(prefix[1])
    let sourceBytes      = source.buffer
    let destinationBytes = destination.buffer
    let endBlock         = firstBlock + blockCount
    let fullBlockEnd     = Math.min(endBlock, source.count / AesBlockSize)
    var block            = firstBlock
    while block + 4 <= fullBlockEnd
    {
        let offset = block * AesBlockSize
        aes[].xorFourHardware'(false, false)(counter(prefix, low, block),
                              counter(prefix, low, block + 1),
                              counter(prefix, low, block + 2),
                              counter(prefix, low, block + 3),
                              sourceBytes + offset,
                              destinationBytes + offset)
        block += 4
    }

    while block < fullBlockEnd
    {
        let offset = block * AesBlockSize
        let stream = aes[].encryptBlockHardware(counter(prefix, low, block))
        store(destinationBytes + offset, stream ^ load(sourceBytes + offset))
        block += 1
    }

    if block < endBlock
    {
        var tail: [16] u8
        store(&tail[0], aes[].encryptBlockHardware(counter(prefix, low, block)))
        let offset = block * AesBlockSize
        for i in source.count - offset do
            destinationBytes[offset + i] = sourceBytes[offset + i] ^ tail[i]
        Crypto.secureClear(tail)
    }
}

private func aesCtrCryptBlocks(aes: *Aes, initialCounter: [AesCtrCounterSize] u8, source: const [..] u8, destination: [..] u8, firstBlock, blockCount: u64) fail
{
    if aes[].usesHardwareRounds()
    {
        if blockCount == 0 do
            return
        let prefix = cast #bit (U64x2, load(&initialCounter[0]))
        let low    = Swag.byteSwap(prefix[1])
        if firstBlock + blockCount - 1 > Swag.U64.Max - low do
            aesXorCounterBlocksHardware'128(aes, prefix, source, destination, firstBlock, blockCount)
        else do
            aesXorCounterBlocksHardware'64(aes, prefix, source, destination, firstBlock, blockCount)
        return
    }

    var block = 0'u64
    while block < blockCount
    {
        var counter = initialCounter
        if not aesCtrAddCounter(&counter, firstBlock + block) do
            fail Errors.BadParameterError{"AES-CTR counter range overflows 128 bits"}
        var keyStream: [AesCtrCounterSize] u8
        try aes[].encryptBlock(counter, keyStream)
        let offset = (firstBlock + block) * AesCtrCounterSize
        let count  = Math.min(source.count - offset, AesCtrCounterSize)
        for index in count do
            destination[offset + index] = source[offset + index] ^ keyStream[index]
        Crypto.secureClear(counter)
        Crypto.secureClear(keyStream)
        block += 1
    }
}

private func aesCtrCryptBlocksParallel(aes: *Aes, initialCounter: [AesCtrCounterSize] u8, source: const [..] u8, destination: [..] u8, blockCount: u64) fail
{
    const BatchBlocks = 1024
    let batchCount = blockCount / BatchBlocks + cast(u64, (blockCount % BatchBlocks) != 0)
    catch parallel for |&aes, &initialCounter, &source, &destination, blockCount| batch in batchCount
    {
        let firstBlock = batch * BatchBlocks
        let count      = Math.min(blockCount - firstBlock, BatchBlocks)
        try aesCtrCryptBlocks(aes, initialCounter, source, destination, firstBlock, count)
    }
    {
        fail Swag.err
    }
}

// Encrypts or decrypts bytes with AES-CTR using a 16, 24, or 32-byte key.
//
// `initialCounter` and input/output lengths must be exactly 16 bytes and equal, respectively.
// The counter is a 128-bit big-endian integer, incremented once per block. Input and output may
// be the same slice or disjoint; partial overlap is unsupported. Counter overflow fails before
// any output is written. AES-CTR does not authenticate the data, so callers must authenticate it
// with a separate construction before trusting decrypted plaintext.
func aesCtrCrypt(key, initialCounter, input: const [..] u8, output: [..] u8) fail
{
    if initialCounter.count != AesCtrCounterSize or output.count != input.count do
        fail Errors.BadParameterError{"AES-CTR needs a 16-byte counter and matching output length"}

    const BlockSize = cast(u64, AesCtrCounterSize)
    let blockCount = input.count / BlockSize + cast(u64, (input.count % BlockSize) != 0)
    var counter: [AesCtrCounterSize] u8
    Swag.memcpy(&counter[0], initialCounter.buffer, AesCtrCounterSize)
    if blockCount and not aesCtrAddCounter(&counter, blockCount - 1) do
        fail Errors.BadParameterError{"AES-CTR counter range overflows 128 bits"}
    Swag.memcpy(&counter[0], initialCounter.buffer, AesCtrCounterSize)

    var aes = try Aes.create(key)
    defer aes.clear()
    if input.count < 64 * 1024 or Swag.workerCount() <= 1
    {
        try aesCtrCryptBlocks(&aes, counter, input, output, 0, blockCount)
        Crypto.secureClear(counter)
        return
    }

    try aesCtrCryptBlocksParallel(&aes, counter, input, output, blockCount)
    Crypto.secureClear(counter)
}
