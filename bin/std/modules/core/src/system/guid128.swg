#global public

using Core.Errors

// Thread-local storage for random number generation and identifier counter.
#[Swag.Tls]
{
    private var g_Rng: Random.MersenneTwister64     // Mersenne Twister 64-bit random number generator
    private var g_RngInit: bool                     // Flag indicating whether the RNG has been initialized
    private var g_Counter: u32                      // Thread-local counter for timestamp-based identifiers
}

// Initialize the random number generator with high-entropy seed.
// Uses multiple time-based and hardware-based entropy sources for better randomness.
#[Swag.Inline]
private func initRng()
{
    if !g_RngInit
    {
        var seed: [3] u64 = undefined
        seed[0] = Time.monotonicMilliseconds()
        seed[1] = Time.monotonicMicroseconds()
        seed[2] = Hardware.macAddress()
        g_Rng.seedU64(seed)
        g_RngInit = true
    }
}

// Stores a 128-bit identifier and creates RFC 4122 version-4 UUID values.
struct Guid128
{
    public readonly using value: union
    {
        bytes: [16] u8     // Byte representation.
        words: [2] u64     // Two-word representation.
    }
}

impl Guid128
{
    private func hexDigit(character: u8)->{ value: u8, valid: bool }
    {
        if character >= '0' and character <= '9' do
            return {character - '0'u8, true}
        if character >= 'a' and character <= 'f' do
            return {character - 'a'u8 + 10, true}
        if character >= 'A' and character <= 'F' do
            return {character - 'A'u8 + 10, true}
        return {0, false}
    }

    // Returns whether both identifiers have the same bits.
    mtd const opEquals(other: Guid128)->bool
    {
        return .words[0] == other.words[0] and .words[1] == other.words[1]
    }

    // Creates a random RFC 4122 version-4 UUID.
    func random()->Guid128
    {
        initRng()
        var result: retval = undefined
        result.words[0] = g_Rng.nextU64()
        result.words[1] = g_Rng.nextU64()
        result.bytes[6] = (result.bytes[6] & 0x0F) | 0x40     // Version 4
        result.bytes[8] = (result.bytes[8] & 0x3F) | 0x80     // RFC 4122 variant
        return result
    }

    // Resets the identifier to its null value.
    mtd clear()
    {
        .words[0], .words[1] = 0
    }

    // Returns whether all bits are zero.
    mtd const isNull()->bool => .words[0] == 0 and .words[1] == 0

    // Convert guid to a string of the form xxxxxxxx-xxxx-Mxxx-Nxxx-xxxxxxxxxxxx
    #[Swag.Safety(.BoundCheck, false)]
    mtd const toString(result: [..] u8)
    {
        Debug.assert(@countof(result) == 36)

        const Tbl = "0123456789abcdef"

        result[0] = Tbl[(.bytes[0] >> 4)]
        result[1] = Tbl[(.bytes[0] & 0xF)]
        result[2] = Tbl[(.bytes[1] >> 4)]
        result[3] = Tbl[(.bytes[1] & 0xF)]
        result[4] = Tbl[(.bytes[2] >> 4)]
        result[5] = Tbl[(.bytes[2] & 0xF)]
        result[6] = Tbl[(.bytes[3] >> 4)]
        result[7] = Tbl[(.bytes[3] & 0xF)]
        result[8] = '-'

        result[9]  = Tbl[(.bytes[4] >> 4)]
        result[10] = Tbl[(.bytes[4] & 0xF)]
        result[11] = Tbl[(.bytes[5] >> 4)]
        result[12] = Tbl[(.bytes[5] & 0xF)]
        result[13] = '-'

        result[14] = Tbl[(.bytes[6] >> 4)]
        result[15] = Tbl[(.bytes[6] & 0xF)]
        result[16] = Tbl[(.bytes[7] >> 4)]
        result[17] = Tbl[(.bytes[7] & 0xF)]
        result[18] = '-'

        result[19] = Tbl[(.bytes[8] >> 4)]
        result[20] = Tbl[(.bytes[8] & 0xF)]
        result[21] = Tbl[(.bytes[9] >> 4)]
        result[22] = Tbl[(.bytes[9] & 0xF)]
        result[23] = '-'

        result[24] = Tbl[(.bytes[10] >> 4)]
        result[25] = Tbl[(.bytes[10] & 0xF)]
        result[26] = Tbl[(.bytes[11] >> 4)]
        result[27] = Tbl[(.bytes[11] & 0xF)]
        result[28] = Tbl[(.bytes[12] >> 4)]
        result[29] = Tbl[(.bytes[12] & 0xF)]
        result[30] = Tbl[(.bytes[13] >> 4)]
        result[31] = Tbl[(.bytes[13] & 0xF)]
        result[32] = Tbl[(.bytes[14] >> 4)]
        result[33] = Tbl[(.bytes[14] & 0xF)]
        result[34] = Tbl[(.bytes[15] >> 4)]
        result[35] = Tbl[(.bytes[15] & 0xF)]
    }

    // Returns the canonical lowercase UUID representation.
    mtd const toString()->String
    {
        var result: retval
        result.reserve(36)
        result.length = 36
        .toString(result.toSlice())
        return result
    }

    // Parses the canonical `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` form.
    func parse(str: string)->Guid128 fail
    {
        var result: retval
        if !tryParse(str, &result) do
            fail InvalidFormatError{"invalid 128-bit identifier"}
        return result
    }

    // Tries to parse the canonical `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` form.
    func tryParse(str: string, result: *Guid128)->bool
    {
        if @countof(str) != 36 do
            return false

        var parsed: Guid128
        var sourceIndex = 0'u64
        for byteIndex in 16
        {
            if sourceIndex == 8 or sourceIndex == 13 or sourceIndex == 18 or sourceIndex == 23
            {
                if str[sourceIndex] != '-' do
                    return false
                sourceIndex += 1
            }

            let {value: high, valid: highValid} = hexDigit(str[sourceIndex])
            let {value: low, valid: lowValid}   = hexDigit(str[sourceIndex + 1])
            if !highValid or !lowValid do
                return false

            parsed.bytes[byteIndex] = (high << 4) | low
            sourceIndex             += 2
        }

        result[] = parsed
        return true
    }
}

// String conversion interface implementation for Guid128.
// Enables automatic string conversion in formatting contexts.
impl StrConv.IConvert for Guid128
{
    // Convert the identifier to its string representation for display.
    // Uses the standard UUID format with hyphens.
    mtd const impl convert(buf: *ConcatBuffer, convFmt: StrConv.ConvertFormat, strFormat: #null string)
    {
        buf.addBytes(.toString())
    }
}

// Hash interface implementation for Guid128.
// Enables use of Guid128 as keys in hash tables and sets.
impl Hash.IHash32 for Guid128
{
    // Compute a 32-bit hash value for the identifier.
    // Uses CRC32 algorithm on the entire 16-byte identifier data.
    mtd const impl compute()->u32
    {
        return Hash.Crc32.compute(@mkslice(&.bytes[0], 16))
    }
}
