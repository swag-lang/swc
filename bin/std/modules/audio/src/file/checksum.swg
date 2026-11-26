using Core.Math

// Advances the polynomial x^0 by a fixed number of bits in GF(2).
private func checksumPower(bits, degree, polynomial: u32)->u64
{
    let top     = 1'u64 << degree
    let divisor = top | polynomial
    var value   = 1'u64
    for bits
    {
        value <<= 1
        if value & top do
            value ^= divisor
    }

    return value
}

// Folds whole 16-byte blocks to a single MSB-first block. Updating a checksum from zero
// with the result gives the same remainder as updating it from `initial` with `bytes`.
// The caller supplies at least four blocks and finishes any partial block separately.
func(Degree: u32, Polynomial: u32, OggHeader: bool = false) foldMsbChecksum(bytes: const [..] u8, initial: u32)->[16] u8
{
    const ReverseBytes = cast(Simd.U8x16, [15'u8, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
    const NextBlock    = cast(Simd.U64x2, [#run checksumPower(128, Degree, Polynomial), #run checksumPower(192, Degree, Polynomial)])
    const NextGroup    = cast(Simd.U64x2, [#run checksumPower(512, Degree, Polynomial), #run checksumPower(576, Degree, Polynomial)])

    #[Swag.Inline]
    func loadBlock(source: const [*] u8)->Simd.U64x2
        => cast #bit (Simd.U64x2, Simd.shuffle(Simd.load(source), ReverseBytes))

    // The high half is 64 degrees above the low half. Each lane's power includes that offset.
    #[Swag.Inline]
    func fold(value, powers, next: Simd.U64x2)->Simd.U64x2
        => Simd.clmulLowLow(value, powers) ^ Simd.clmulHighHigh(value, powers) ^ next

    let source = unwrap bytes.buffer
    let seed   = [0'u64, cast(u64, initial) << (64 - Degree)]
    var first  = loadBlock(source) ^ Simd.load(cast(const [*] u64, &seed[0]))
    var second = loadBlock(source + 16)
    #static if OggHeader
    {
        // Ogg's four checksum bytes are at positions six through nine in this block.
        const ChecksumMask = cast(Simd.U8x16, [255'u8, 255, 255, 255, 255, 255, 0, 0, 0, 0, 255, 255, 255, 255, 255, 255])
        second &= cast #bit(Simd.U64x2, ChecksumMask)
    }

    var third  = loadBlock(source + 32)
    var fourth = loadBlock(source + 48)

    // Advance four independent accumulators to overlap carry-less multiplication latency.
    var offset = 64'u64
    while offset + 64 <= bytes.count
    {
        first  = fold(first, NextGroup, loadBlock(source + offset))
        second = fold(second, NextGroup, loadBlock(source + offset + 16))
        third  = fold(third, NextGroup, loadBlock(source + offset + 32))
        fourth = fold(fourth, NextGroup, loadBlock(source + offset + 48))
        offset += 64
    }

    // Collapse the interleaved groups in byte order.
    first = fold(first, NextBlock, second)
    first = fold(first, NextBlock, third)
    first = fold(first, NextBlock, fourth)
    while offset < bytes.count
    {
        first  = fold(first, NextBlock, loadBlock(source + offset))
        offset += 16
    }

    var block: #returntype
    Simd.store(cast([*] u8, &block[0]), Simd.shuffle(cast #bit (Simd.U8x16, first), ReverseBytes))
    return block
}
