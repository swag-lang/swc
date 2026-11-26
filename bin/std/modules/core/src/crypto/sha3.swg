#global namespace Hash
#global #[Swag.Safety(.Overflow, false)]

// Largest rate used by the SHA-3 and SHAKE sponge functions, in bytes.
public const Sha3MaxRate = 168

// Stores a SHA-3 sequence that selects one of four standard digest sizes.
//
// The digest size is bound by the domain separator and padding.
#[Swag.NoCopy, Swag.Opaque]
public struct Sha3
{
    state:      [25] u64
    buffer:     [Sha3MaxRate] u8
    bufferSize: u64
    rate:       u64
    digestSize: u64
}

private const KeccakRoundConstants: [24] u64 = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]

#[Swag.Inline]
private func keccakChi(row: [*] u64, a, b, c, d, e: u64)
{
    row[0] = a ^ (~b & c)
    row[1] = b ^ (~c & d)
    row[2] = c ^ (~d & e)
    row[3] = d ^ (~e & a)
    row[4] = e ^ (~a & b)
}

private func permuteKeccak(state: *[25] u64)
{
    let lanes = state[].buffer
    for roundConstant in KeccakRoundConstants
    {
        // Theta mixes the parity of each column into the neighboring columns.
        let c0 = lanes[0] ^ lanes[5] ^ lanes[10] ^ lanes[15] ^ lanes[20]
        let c1 = lanes[1] ^ lanes[6] ^ lanes[11] ^ lanes[16] ^ lanes[21]
        let c2 = lanes[2] ^ lanes[7] ^ lanes[12] ^ lanes[17] ^ lanes[22]
        let c3 = lanes[3] ^ lanes[8] ^ lanes[13] ^ lanes[18] ^ lanes[23]
        let c4 = lanes[4] ^ lanes[9] ^ lanes[14] ^ lanes[19] ^ lanes[24]

        let d0 = c4 ^ Math.rol(c1, 1)
        let d1 = c0 ^ Math.rol(c2, 1)
        let d2 = c1 ^ Math.rol(c3, 1)
        let d3 = c2 ^ Math.rol(c4, 1)
        let d4 = c3 ^ Math.rol(c0, 1)

        // Rotate and permute the theta-adjusted lanes into their destination rows.
        let b00 = lanes[0] ^ d0
        let b10 = Math.rol(lanes[6] ^ d1, 44)
        let b20 = Math.rol(lanes[12] ^ d2, 43)
        let b30 = Math.rol(lanes[18] ^ d3, 21)
        let b40 = Math.rol(lanes[24] ^ d4, 14)

        let b01 = Math.rol(lanes[3] ^ d3, 28)
        let b11 = Math.rol(lanes[9] ^ d4, 20)
        let b21 = Math.rol(lanes[10] ^ d0, 3)
        let b31 = Math.rol(lanes[16] ^ d1, 45)
        let b41 = Math.rol(lanes[22] ^ d2, 61)

        let b02 = Math.rol(lanes[1] ^ d1, 1)
        let b12 = Math.rol(lanes[7] ^ d2, 6)
        let b22 = Math.rol(lanes[13] ^ d3, 25)
        let b32 = Math.rol(lanes[19] ^ d4, 8)
        let b42 = Math.rol(lanes[20] ^ d0, 18)

        let b03 = Math.rol(lanes[4] ^ d4, 27)
        let b13 = Math.rol(lanes[5] ^ d0, 36)
        let b23 = Math.rol(lanes[11] ^ d1, 10)
        let b33 = Math.rol(lanes[17] ^ d2, 15)
        let b43 = Math.rol(lanes[23] ^ d3, 56)

        let b04 = Math.rol(lanes[2] ^ d2, 62)
        let b14 = Math.rol(lanes[8] ^ d3, 55)
        let b24 = Math.rol(lanes[14] ^ d4, 39)
        let b34 = Math.rol(lanes[15] ^ d0, 41)
        let b44 = Math.rol(lanes[21] ^ d1, 2)

        // Chi combines adjacent lanes within each row. Iota adjusts the first lane.
        keccakChi(lanes, b00, b10, b20, b30, b40)
        keccakChi(lanes + 5, b01, b11, b21, b31, b41)
        keccakChi(lanes + 10, b02, b12, b22, b32, b42)
        keccakChi(lanes + 15, b03, b13, b23, b33, b43)
        keccakChi(lanes + 20, b04, b14, b24, b34, b44)
        lanes[0] ^= roundConstant
    }
}

public impl Sha3
{
    // Creates a SHA-3 sequence for one of the standard digest sizes: 28, 32, 48, or 64 bytes.
    func create(digestSize: u64)->Sha3 fail
    {
        var result: #returntype
        try result.reset(digestSize)
        return result
    }

    // Replaces prior state and starts a SHA-3 sequence for a supported digest size.
    mtd reset(digestSize: u64) fail
    {
        var rate: u64
        switch digestSize
        {
        case 28: rate = 144
        case 32: rate = 136
        case 48: rate = 104
        case 64: rate = 72
        default: rate = 0
        }

        if not rate do
            fail Errors.BadParameterError{"SHA-3 digest size must be 28, 32, 48, or 64 bytes"}

        .clear()
        .rate       = rate
        .digestSize = digestSize
    }

    // Includes `data` in the running SHA-3 digest.
    mtd update(data: const [..] u8)
    {
        Swag.assert(.rate != 0, "SHA-3 needs an initialized sequence")
        var offset = 0'u64
        while offset < data.count
        {
            let count = Math.min(data.count - offset, .rate - .bufferSize)
            Swag.memcpy(&.buffer[.bufferSize], data.buffer + offset, count)
            .bufferSize += count
            offset      += count
            if .bufferSize == .rate do
                .absorbBuffer()
        }
    }

    // Finalizes the sequence into a destination of exactly the configured digest size and clears the sponge state.
    mtd finalize(destination: [..] u8) fail
    {
        if not .rate do
            fail Errors.BadParameterError{"SHA-3 needs an initialized sequence"}
        if destination.count != .digestSize do
            fail Errors.BadParameterError{"SHA-3 destination length must match the configured digest size"}

        .buffer[.bufferSize] = 0x06
        Swag.memset(.buffer.buffer + .bufferSize + 1, 0, .rate - .bufferSize - 1)
        .buffer[.rate - 1] |= 0x80
        .absorbBuffer()
        .squeeze(destination)
        .clear()
    }

    // Clears the sponge state and configured output length.
    mtd clear()
    {
        Crypto.secureClear(.state)
        Crypto.secureClear(.buffer)
        .bufferSize = 0
        .rate       = 0
        .digestSize = 0
    }

    // Computes a SHA-3 digest in one operation.
    //
    // `destination.count` selects the standard digest size: 28, 32, 48, or 64 bytes.
    func compute(data: const [..] u8, destination: [..] u8) fail
    {
        var digest = try Sha3.create(destination.count)
        digest.update(data)
        try digest.finalize(destination)
    }

    private mtd absorbBuffer()
    {
        let laneCount = .rate / 8
        for lane in laneCount
        {
            var word = 0'u64
            for byte in 8 do
                word |= cast(u64, .buffer[lane * 8 + byte]) << cast(u32, byte * 8)
            .state[lane] ^= word
        }

        permuteKeccak(&.state)
        Crypto.secureClear(.buffer)
        .bufferSize = 0
    }

    private mtd squeeze(destination: [..] u8)
    {
        var written = 0'u64
        while written < destination.count
        {
            let count = Math.min(destination.count - written, .rate)
            for index in count
            {
                let lane  = index / 8
                let shift = cast(u32, (index % 8) * 8)
                destination[written + index] = cast(u8, (.state[lane] >> shift) & 0xFF)
            }

            written += count
            if written < destination.count do
                permuteKeccak(&.state)
        }
    }

    // Clears state when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }
}

// Stores a SHAKE extendable-output sequence.
//
// Output bytes are generated only when `finalize` is called, so callers choose any output length at that point.
#[Swag.NoCopy, Swag.Opaque]
public struct Shake
{
    state:      [25] u64
    buffer:     [Sha3MaxRate] u8
    bufferSize: u64
    rate:       u64
    suffix:     u8
}

public impl Shake
{
    // Creates a SHAKE128 or SHAKE256 sequence.
    func create(securityBits: u64)->Shake fail
    {
        var result: #returntype
        try result.reset(securityBits)
        return result
    }

    // Creates an internal cSHAKE128 or cSHAKE256 sponge with the cSHAKE domain separator.
    //
    // The caller supplies the SP 800-185 function-name and customization bytepads as input.
    internal func createCShake(securityBits: u64)->Shake fail
    {
        var result: #returntype
        try result.resetCShake(securityBits)
        return result
    }

    // Replaces prior state and selects SHAKE128 or SHAKE256 with 128 or 256 security bits.
    mtd reset(securityBits: u64) fail
    {
        if securityBits != 128 and securityBits != 256 do
            fail Errors.BadParameterError{"SHAKE security strength must be 128 or 256 bits"}

        .clear()
        .rate   = securityBits == 128 ? 168 : 136
        .suffix = 0x1F
    }

    // Replaces prior state and selects cSHAKE128 or cSHAKE256 with its domain separator.
    internal mtd resetCShake(securityBits: u64) fail
    {
        if securityBits != 128 and securityBits != 256 do
            fail Errors.BadParameterError{"cSHAKE security strength must be 128 or 256 bits"}

        .clear()
        .rate   = securityBits == 128 ? 168 : 136
        .suffix = 0x04
    }

    // Includes `data` in the running SHAKE input.
    mtd update(data: const [..] u8)
    {
        Swag.assert(.rate != 0, "SHAKE needs an initialized sequence")
        var offset = 0'u64
        while offset < data.count
        {
            let count = Math.min(data.count - offset, .rate - .bufferSize)
            Swag.memcpy(&.buffer[.bufferSize], data.buffer + offset, count)
            .bufferSize += count
            offset      += count
            if .bufferSize == .rate do
                .absorbBuffer()
        }
    }

    // Finalizes the input into any requested number of output bytes, then clears the sponge state.
    mtd finalize(destination: [..] u8) fail
    {
        if not .rate do
            fail Errors.BadParameterError{"SHAKE needs an initialized sequence"}

        .buffer[.bufferSize] = .suffix
        Swag.memset(.buffer.buffer + .bufferSize + 1, 0, .rate - .bufferSize - 1)
        .buffer[.rate - 1] |= 0x80
        .absorbBuffer()
        .squeeze(destination)
        .clear()
    }

    // Clears the sponge state and selected variant.
    mtd clear()
    {
        Crypto.secureClear(.state)
        Crypto.secureClear(.buffer)
        .bufferSize = 0
        .rate       = 0
        .suffix     = 0
    }

    // Computes SHAKE output in one operation.
    //
    // `securityBits` selects SHAKE128 or SHAKE256; destination length selects the output length.
    func compute(data: const [..] u8, securityBits: u64, destination: [..] u8) fail
    {
        var shake = try Shake.create(securityBits)
        shake.update(data)
        try shake.finalize(destination)
    }

    private mtd absorbBuffer()
    {
        let laneCount = .rate / 8
        for lane in laneCount
        {
            var word = 0'u64
            for byte in 8 do
                word |= cast(u64, .buffer[lane * 8 + byte]) << cast(u32, byte * 8)
            .state[lane] ^= word
        }

        permuteKeccak(&.state)
        Crypto.secureClear(.buffer)
        .bufferSize = 0
    }

    private mtd squeeze(destination: [..] u8)
    {
        var written = 0'u64
        while written < destination.count
        {
            let count = Math.min(destination.count - written, .rate)
            for index in count
            {
                let lane  = index / 8
                let shift = cast(u32, (index % 8) * 8)
                destination[written + index] = cast(u8, (.state[lane] >> shift) & 0xFF)
            }

            written += count
            if written < destination.count do
                permuteKeccak(&.state)
        }
    }

    // Clears state when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }
}
