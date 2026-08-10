#global public

using Core.Errors

// Thread-local storage for identifier generation.
#[Swag.Tls]
{
    private var g_Rng: Random.MersenneTwister64     // Mersenne Twister 64-bit random number generator
    private var g_RngInit: bool                     // Flag indicating whether the RNG has been initialized
    private var g_Counter: u32                      // Thread-local counter for timestamp-based GUIDs
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

// Stores a compact 64-bit identifier.
//
// Unlike [[Core.Guid128]], a random `Guid64` cannot provide UUID-level collision
// resistance. Use it for local object identities and temporary names, not as a
// security token or a globally coordinated database key.
#[Swag.Operators(opEquals)]
struct Guid64
{
    public readonly value: u64     // Raw 64-bit representation.
}

impl Guid64
{
    // Creates an identifier containing seconds, milliseconds, a thread-local counter, and randomness.
    func timestamped()->Guid64
    {
        initRng()

        var result: retval = undefined
        let now            = Time.DateTime.now()

        // Extract components
        let dateTicks = Time.dateToTicks(now.year, now.month, now.day) +
                        Time.timeToTicks(now.hour, now.minute, now.second, now.millisecond)
        let timestamp   = cast(u32) ((dateTicks - Time.DaysTo1970 * Time.TicksPerDay) / Time.TicksPerSecond)
        let millisecond = now.millisecond

        // Thread-local counter with overflow protection
        g_Counter = (g_Counter + 1) & 0xFFF     // 12-bit counter (0-4095)

        let random4 = cast(u8) (g_Rng.nextU64() & 0xF)     // 4-bit random

        // Combine all components
        result.value = 0
        result.value |= cast(u64) timestamp << 32       // Upper 32 bits: timestamp
        result.value |= cast(u64) millisecond << 16     // Next 16 bits: milliseconds
        result.value |= cast(u64) g_Counter << 4        // Next 12 bits: counter
        result.value |= cast(u64) random4               // Lower 4 bits: random

        return result
    }

    // Creates a pseudorandom 64-bit identifier.
    func random()->Guid64
    {
        initRng()

        var result: retval = undefined
        result.value = g_Rng.nextU64()
        return result
    }

    // Creates an identifier by mixing pseudorandom, clock, process, and thread state.
    func highEntropy()->Guid64
    {
        initRng()

        var result: retval = undefined
        let nowMs          = Time.monotonicMilliseconds()
        let nowUs          = Time.monotonicMicroseconds()
        let pid            = cast(u64) Env.Process.currentProcessId()
        let tid            = cast(u64) Env.Process.currentThreadId()

        // Mix multiple entropy sources using XOR
        result.value = g_Rng.nextU64()
        result.value ^= nowMs
        result.value ^= (nowUs << 16)
        result.value ^= (pid << 32)
        result.value ^= (tid << 8)

        return result
    }

    // Resets the identifier to its null value.
    mtd clear()
    {
        .value = 0
    }

    // Returns whether all bits are zero.
    mtd isNull()->bool
    {
        return .value == 0
    }

    // Writes exactly 16 uppercase hexadecimal digits to `result`.
    mtd const toString(result: [..] u8)
    {
        Debug.assert(@countof(result) == 16)

        const Tbl = "0123456789ABCDEF"

        // Convert each nibble to hex, starting from most significant
        // Unroll the loop for better performance
        var idx = .value
        result[15] = Tbl[idx & 0xF]
        idx        >>= 4
        result[14] = Tbl[idx & 0xF]
        idx        >>= 4
        result[13] = Tbl[idx & 0xF]
        idx        >>= 4
        result[12] = Tbl[idx & 0xF]
        idx        >>= 4
        result[11] = Tbl[idx & 0xF]
        idx        >>= 4
        result[10] = Tbl[idx & 0xF]
        idx        >>= 4
        result[9]  = Tbl[idx & 0xF]
        idx        >>= 4
        result[8]  = Tbl[idx & 0xF]
        idx        >>= 4
        result[7]  = Tbl[idx & 0xF]
        idx        >>= 4
        result[6]  = Tbl[idx & 0xF]
        idx        >>= 4
        result[5]  = Tbl[idx & 0xF]
        idx        >>= 4
        result[4]  = Tbl[idx & 0xF]
        idx        >>= 4
        result[3]  = Tbl[idx & 0xF]
        idx        >>= 4
        result[2]  = Tbl[idx & 0xF]
        idx        >>= 4
        result[1]  = Tbl[idx & 0xF]
        idx        >>= 4
        result[0]  = Tbl[idx & 0xF]
    }

    // Returns 16 uppercase hexadecimal digits.
    mtd const toString()->String
    {
        var result: retval
        result.reserve(16)
        result.length = 16
        .toString(result.toSlice())
        return result
    }

    // Parses exactly 16 hexadecimal digits, with an optional `0x` prefix.
    func parse(str: string)->Guid64 fail
    {
        var result: retval
        if !tryParse(str, &result) do
            fail InvalidFormatError{"invalid 64-bit identifier"}
        return result
    }

    // Tries to parse exactly 16 hexadecimal digits, with an optional `0x` prefix.
    func tryParse(str: string, result: *Guid64)->bool
    {
        var startIndex = 0'u64

        if @countof(str) >= 2 and str[0] == '0' and (str[1] == 'x' or str[1] == 'X') do
            startIndex = 2
        if @countof(str) - startIndex != 16 do
            return false

        var value: u64 = 0
        for [i] in 16
        {
            let c = str[startIndex + i]
            var digit: u64

            if c >= '0' and c <= '9' do
                digit = cast(u64) (c - '0')
            elif c >= 'A' and c <= 'F' do
                digit = cast(u64) (c - 'A' + 10)
            elif c >= 'a' and c <= 'f' do
                digit = cast(u64) (c - 'a' + 10)
            else do
                return false

            value = (value << 4) | digit
        }

        result.value = value
        return true
    }
}

// String conversion interface implementation for Guid64.
// Enables automatic string conversion in formatting contexts.
impl StrConv.IConvert for Guid64
{
    // Convert the GUID to its hexadecimal string representation.
    // Produces a 16-character uppercase hex string without separators.
    mtd const impl convert(buf: *ConcatBuffer, convFmt: StrConv.ConvertFormat, strFormat: #null string)
    {
        buf.addBytes(.toString())
    }
}

// Hash interface implementation for Guid64.
// Enables use of Guid64 as keys in hash tables and sets.
impl Hash.IHash32 for Guid64
{
    // Compute a 32-bit hash value for the GUID.
    // Uses CRC32 algorithm on the 8-byte GUID data for consistent hashing.
    mtd const impl compute()->u32
    {
        return Hash.Crc32.compute(@mkslice(cast(const [*] u8) &.value, #sizeof(u64)))
    }
}
