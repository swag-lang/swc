#global public

using Core.Errors

// Each thread draws identifiers from its own generator and counter, so creation never takes a lock.

tls
{
    private var g_Rng:     Random.MersenneTwister64     // Generator of this thread
    private var g_RngInit: bool                         // Whether the generator of this thread is seeded
    private var g_Counter: u32                          // Counter of this thread for timestamped identifiers
}

// Seeds the generator of the calling thread on first use, from the clocks and the MAC address.
#[Swag.Inline]
private func initRng()
{
    if not g_RngInit
    {
        var seed: [3] u64
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
    // Creates an identifier that orders by creation time.
    //
    // From the most significant bits: 32 bits of seconds since 1970 in local time, 16 bits of
    // milliseconds, a 12-bit counter of the calling thread, then 4 random bits.
    func timestamped()->Guid64
    {
        initRng()

        var result: retval
        let now = Time.DateTime.now()

        let dateTicks = Time.dateToTicks(now.year, now.month, now.day) +
                        Time.timeToTicks(now.hour, now.minute, now.second, now.millisecond)
        let timestamp   = cast(u32) ((dateTicks - Time.DaysTo1970 * Time.TicksPerDay) / Time.TicksPerSecond)
        let millisecond = now.millisecond

        g_Counter = (g_Counter + 1) & 0xFFF
        let random4 = cast(u8) (g_Rng.nextU64() & 0xF)

        result.value = 0
        result.value |= cast(u64) timestamp << 32
        result.value |= cast(u64) millisecond << 16
        result.value |= cast(u64) g_Counter << 4
        result.value |= cast(u64) random4

        return result
    }

    // Creates a pseudorandom 64-bit identifier from the generator of the calling thread.
    func random()->Guid64
    {
        initRng()

        var result: retval
        result.value = g_Rng.nextU64()
        return result
    }

    // Creates an identifier by mixing pseudorandom, clock, process, and thread state.
    func highEntropy()->Guid64
    {
        initRng()

        var result: retval
        let nowMs = Time.monotonicMilliseconds()
        let nowUs = Time.monotonicMicroseconds()
        let pid   = cast(u64) Env.Process.currentProcessId()
        let tid   = cast(u64) Env.Process.currentThreadId()

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
    mtd const isNull()->bool => .value == 0

    // Writes exactly 16 uppercase hexadecimal digits to `result`.
    mtd const toString(result: [..] u8)
    {
        Swag.assert(result.count == 16)

        const Tbl = "0123456789ABCDEF"

        // The least significant nibble goes last.
        var bits = .value
        for i in reversed(16)
        {
            result[i] = Tbl[bits & 0xF]
            bits      >>= 4
        }
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
        if not tryParse(str, &result) do
            fail InvalidFormatError{"invalid 64-bit identifier"}
        return result
    }

    // Parses exactly 16 hexadecimal digits, with an optional `0x` prefix, into `result` and returns whether it succeeded.
    //
    // `result` is unchanged on failure.
    func tryParse(str: string, result: *Guid64)->bool
    {
        var startIndex = 0'u64

        if str.count >= 2 and str[0] == '0' and (str[1] == 'x' or str[1] == 'X') do
            startIndex = 2
        if str.count - startIndex != 16 do
            return false

        var value: u64 = 0
        for i in 16
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

// Formats a [[Core.Guid64]] as 16 uppercase hexadecimal digits.
impl StrConv.IConvert for Guid64
{
    mtd const impl convert(buf: *ConcatBuffer, convFmt: StrConv.ConvertFormat, strFormat: string?)
    {
        buf.addBytes(.toString())
    }
}

// Hashes the 8 bytes of a [[Core.Guid64]] with CRC-32, so it can key a hash table or a set.
impl Hash.IHash32 for Guid64
{
    mtd const impl compute()->u32 => Hash.Crc32.compute(Swag.makeSlice(cast(const [*] u8) &.value, #sizeof(u64)))
}
