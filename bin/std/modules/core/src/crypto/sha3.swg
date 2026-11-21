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

private const KeccakRotation: [25] u8 = [
    0, 1, 62, 28, 27,
    36, 44, 6, 55, 20,
    3, 10, 43, 25, 39,
    41, 45, 15, 21, 8,
    18, 2, 61, 56, 14]

private func rotateLeft64(value: u64, count: u8)->u64
{
    if not count do
        return value
    return (value << count) | (value >> (64 - count))
}

private func permuteKeccak(state: *[25] u64)
{
    for round in 24
    {
        var columns: [5] u64
        for x in 5 do
            columns[x] = state[][x] ^ state[][x + 5] ^ state[][x + 10] ^ state[][x + 15] ^ state[][x + 20]

        for x in 5
        {
            let delta = columns[(x + 4) % 5] ^ rotateLeft64(columns[(x + 1) % 5], 1)
            for y in 5 do
                state[][x + 5 * y] ^= delta
        }

        var lanes: [25] u64
        for x in 5
        {
            for y in 5
            {
                let source = x + 5 * y
                let target = y + 5 * ((2 * x + 3 * y) % 5)
                lanes[target] = rotateLeft64(state[][source], KeccakRotation[source])
            }
        }

        for x in 5
        {
            for y in 5
            {
                let index = x + 5 * y
                state[][index] = lanes[index] ^ ((~lanes[(x + 1) % 5 + 5 * y]) & lanes[(x + 2) % 5 + 5 * y])
            }
        }

        state[][0] ^= KeccakRoundConstants[round]
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

    // Replaces prior state and selects SHAKE128 or SHAKE256 with 128 or 256 security bits.
    mtd reset(securityBits: u64) fail
    {
        if securityBits != 128 and securityBits != 256 do
            fail Errors.BadParameterError{"SHAKE security strength must be 128 or 256 bits"}

        .clear()
        .rate   = securityBits == 128 ? 168 : 136
        .suffix = 0x1F
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
