#global private

// Real-life example: data integrity toolkit combining Adler-32 checksums with
// bit manipulation utilities. Exercises struct+impl, const lookup tables,
// bitwise operations, overloads, slices, and integer tricks from std/core.

// ---- Bit reversal (from std/core math/bits.swg) ----------------------------

const Rev8Arr: [256] u8 = [
    0x00, 0x80, 0x40, 0xC0, 0x20, 0xA0, 0x60, 0xE0, 0x10, 0x90, 0x50, 0xD0, 0x30, 0xB0, 0x70, 0xF0,
    0x08, 0x88, 0x48, 0xC8, 0x28, 0xA8, 0x68, 0xE8, 0x18, 0x98, 0x58, 0xD8, 0x38, 0xB8, 0x78, 0xF8,
    0x04, 0x84, 0x44, 0xC4, 0x24, 0xA4, 0x64, 0xE4, 0x14, 0x94, 0x54, 0xD4, 0x34, 0xB4, 0x74, 0xF4,
    0x0C, 0x8C, 0x4C, 0xCC, 0x2C, 0xAC, 0x6C, 0xEC, 0x1C, 0x9C, 0x5C, 0xDC, 0x3C, 0xBC, 0x7C, 0xFC,
    0x02, 0x82, 0x42, 0xC2, 0x22, 0xA2, 0x62, 0xE2, 0x12, 0x92, 0x52, 0xD2, 0x32, 0xB2, 0x72, 0xF2,
    0x0A, 0x8A, 0x4A, 0xCA, 0x2A, 0xAA, 0x6A, 0xEA, 0x1A, 0x9A, 0x5A, 0xDA, 0x3A, 0xBA, 0x7A, 0xFA,
    0x06, 0x86, 0x46, 0xC6, 0x26, 0xA6, 0x66, 0xE6, 0x16, 0x96, 0x56, 0xD6, 0x36, 0xB6, 0x76, 0xF6,
    0x0E, 0x8E, 0x4E, 0xCE, 0x2E, 0xAE, 0x6E, 0xEE, 0x1E, 0x9E, 0x5E, 0xDE, 0x3E, 0xBE, 0x7E, 0xFE,
    0x01, 0x81, 0x41, 0xC1, 0x21, 0xA1, 0x61, 0xE1, 0x11, 0x91, 0x51, 0xD1, 0x31, 0xB1, 0x71, 0xF1,
    0x09, 0x89, 0x49, 0xC9, 0x29, 0xA9, 0x69, 0xE9, 0x19, 0x99, 0x59, 0xD9, 0x39, 0xB9, 0x79, 0xF9,
    0x05, 0x85, 0x45, 0xC5, 0x25, 0xA5, 0x65, 0xE5, 0x15, 0x95, 0x55, 0xD5, 0x35, 0xB5, 0x75, 0xF5,
    0x0D, 0x8D, 0x4D, 0xCD, 0x2D, 0xAD, 0x6D, 0xED, 0x1D, 0x9D, 0x5D, 0xDD, 0x3D, 0xBD, 0x7D, 0xFD,
    0x03, 0x83, 0x43, 0xC3, 0x23, 0xA3, 0x63, 0xE3, 0x13, 0x93, 0x53, 0xD3, 0x33, 0xB3, 0x73, 0xF3,
    0x0B, 0x8B, 0x4B, 0xCB, 0x2B, 0xAB, 0x6B, 0xEB, 0x1B, 0x9B, 0x5B, 0xDB, 0x3B, 0xBB, 0x7B, 0xFB,
    0x07, 0x87, 0x47, 0xC7, 0x27, 0xA7, 0x67, 0xE7, 0x17, 0x97, 0x57, 0xD7, 0x37, 0xB7, 0x77, 0xF7,
    0x0F, 0x8F, 0x4F, 0xCF, 0x2F, 0xAF, 0x6F, 0xEF, 0x1F, 0x9F, 0x5F, 0xDF, 0x3F, 0xBF, 0x7F, 0xFF]

func reverse8(x: u8)->u8
{
    return Rev8Arr[x]
}

func reverse16(x: u16)->u16
{
    return cast(u16) Rev8Arr[x >> 8] | cast(u16) Rev8Arr[x & 0xFF] << 8
}

#[Swag.Safety(.Overflow, false)]
func reverse32(x: u32)->u32
{
    const m0 = 0x55555555'u32
    const m1 = 0x33333333'u32
    const m2 = 0x0F0F0F0F'u32
    var v = ((x >> 1) & m0) | ((x & m0) << 1)
    v = ((v >> 2) & m1) | ((v & m1) << 2)
    v = ((v >> 4) & m2) | ((v & m2) << 4)
    return @byteswap(v)
}

// ---- Integer tricks (from std/core math/integer.swg) -----------------------

#[Swag.Safety(.Overflow, false)]
{
    func isPowerOf2(x: u32)->bool => x != 0 and !(x & (x - 1))
    func isPowerOf2(x: u64)->bool => x != 0 and !(x & (x - 1))
}

#[Swag.Safety(.Overflow, false)]
func hasZeroByte(v: u32)->bool
{
    return cast(bool) ((v - 0x01010101'u32) & ~v & 0x80808080'u32)
}

func makeRepeat32(v: u8)->u32
{
    return (~0'u32 / 255 * cast(u32) v)
}

func hasByte(value: u32, byte: u8)->bool
{
    return hasZeroByte(value ^ makeRepeat32(byte))
}

func gcd(a0, b0: s64)->s64
{
    var a = a0
    var b = b0
    while b != 0
    {
        let temp = b
        b = a % b
        a = temp
    }

    return a
}

func lcm(a, b: s64)->s64
{
    if a > b do
        return a / gcd(a, b) * b
    else do
        return b / gcd(a, b) * a
}

{
    func sign(x: s32) => cast(s32) (x > 0) - cast(s32) (x < 0)
    func sign(x: s64) => cast(s64) (x > 0) - cast(s64) (x < 0)
}

// ---- Adler-32 checksum (from std/core crypto/adler32.swg) ------------------

struct Adler32
{
    adler: u32 = 1
}

impl Adler32
{
    const Base = 65521'u32
    const NMax = 5552'u64

    mtd init()
    {
        .adler = 1
    }

    mtd update(buffer: const [..] u8)
    {
        var s1 = .adler & 0xFFFF
        var s2 = (.adler >> 16) & 0xFFFF

        let count = @countof(buffer)
        if !count do
            return

        let input = @dataof(buffer)
        if count == 1
        {
            s1 += cast(u32) input[0]
            if s1 >= Base do
                s1 -= Base
            s2     += s1
            if s2 >= Base do
                s2 -= Base
        }
        elif count < 16
        {
            for b in buffer
            {
                s1 += cast(u32) b
                s2 += s1
            }

            if s1 >= Base do
                s1 -= Base
            s2     %= Base
        }
        else
        {
            const n = NMax / 16
            var i = 0'u64

            while i + NMax <= count
            {
                for [rounds] in n
                {
                    for [j] in 16'u64
                    {
                        s1 += cast(u32) input[i + j]
                        s2 += s1
                    }

                    i += 16
                }

                s1 %= Base
                s2 %= Base
            }

            if i < count
            {
                while i + 16 <= count
                {
                    for [j] in 16'u64
                    {
                        s1 += cast(u32) input[i + j]
                        s2 += s1
                    }

                    i += 16
                }

                while i < count
                {
                    s1 += cast(u32) input[i]
                    s2 += s1
                    i  += 1
                }

                s1 %= Base
                s2 %= Base
            }
        }

        .adler = s1 | (s2 << 16)
    }

    func compute(buffer: const [..] u8)->u32
    {
        var v: Adler32
        v.init()
        v.update(buffer)
        return v.adler
    }
}

// ---- Data integrity report -------------------------------------------------

struct IntegrityReport
{
    checksum:       u32
    byteCount:      u64
    zeroBytesFound: u32
    bitEntropy:     u32     // sum of popcount over all bytes
    reversedFirst:  u8
    reversedLast:   u8
}

func analyze(data: const [..] u8)->IntegrityReport
{
    var report: IntegrityReport
    report.byteCount = @countof(data)

    if report.byteCount == 0 do
        return report

    report.checksum = Adler32.compute(data)

    let ptr = @dataof(data)
    report.reversedFirst = reverse8(ptr[0])
    report.reversedLast  = reverse8(ptr[report.byteCount - 1])

    var i = 0'u64
    while i + 4 <= report.byteCount
    {
        let word = cast(u32) ptr[i] |
                   cast(u32) ptr[i + 1] << 8 |
                   cast(u32) ptr[i + 2] << 16 |
                   cast(u32) ptr[i + 3] << 24
        if hasZeroByte(word) do
            report.zeroBytesFound += 1
        i                         += 4
    }

    for b in data do
        report.bitEntropy += cast(u32) @bitcountnz(b)

    return report
}

// ---- Tests -----------------------------------------------------------------

// Test Adler-32 against RFC 1950 known vectors
#test
{
    // Empty input
    @assert(Adler32.compute("") == 1)

    // RFC test vector: adler32("Wikipedia") = 0x11E60398
    @assert(Adler32.compute("Wikipedia") == 0x11E60398)

    // Single byte
    @assert(Adler32.compute("a") == 0x00620062)

    // Incremental update matches single-shot compute
    var adler: Adler32
    adler.init()
    adler.update("Wiki")
    adler.update("pedia")
    @assert(adler.adler == Adler32.compute("Wikipedia"))

    // Longer payload exercises the count >= 16 branch
    const payload = "The quick brown fox jumps over the lazy dog"
    var a2: Adler32
    a2.init()
    a2.update(payload)
    let fullChecksum = Adler32.compute(payload)
    @assert(a2.adler == fullChecksum)

    // Three-part split must match bulk update
    var a3: Adler32
    a3.init()
    a3.update("The quick brown ")
    a3.update("fox jumps over ")
    a3.update("the lazy dog")
    @assert(a3.adler == fullChecksum)
}

// Test bit reversal
#test
{
    @assert(reverse8(0x00) == 0x00)
    @assert(reverse8(0xFF) == 0xFF)
    @assert(reverse8(0x01) == 0x80)
    @assert(reverse8(0x80) == 0x01)
    @assert(reverse8(0x0F) == 0xF0)
    @assert(reverse8(0xA5) == 0xA5)     // 10100101 is a palindrome

    // Double-reverse is identity
    for [i] in 256
    {
        let b = cast(u8) i
        @assert(reverse8(reverse8(b)) == b)
    }

    // 16-bit reversal
    @assert(reverse16(0x0001) == 0x8000)
    @assert(reverse16(0x00FF) == 0xFF00)
    @assert(reverse16(reverse16(0xABCD)) == 0xABCD)

    // 32-bit reversal
    @assert(reverse32(0x00000001) == 0x80000000)
    @assert(reverse32(0x80000000) == 0x00000001)
    @assert(reverse32(reverse32(0xDEADBEEF)) == 0xDEADBEEF)
}

// Test integer tricks
#test
{
    // isPowerOf2
    @assert(isPowerOf2(1'u32))
    @assert(isPowerOf2(2'u32))
    @assert(isPowerOf2(4'u32))
    @assert(isPowerOf2(1024'u32))
    @assert(isPowerOf2(0x80000000'u32))
    @assert(!isPowerOf2(0'u32))
    @assert(!isPowerOf2(3'u32))
    @assert(!isPowerOf2(6'u32))
    @assert(!isPowerOf2(0xFFFFFFFF'u32))

    // All u32 powers of 2
    for [i] in 32'u32
    {
        @assert(isPowerOf2(1'u32 << i))
    }

    // hasZeroByte
    @assert(hasZeroByte(0x12003456))
    @assert(hasZeroByte(0x00010101))
    @assert(!hasZeroByte(0x01010101))
    @assert(!hasZeroByte(0xFFFFFFFF))

    // hasByte
    @assert(hasByte(0x12345678, 0x12))
    @assert(hasByte(0x12345678, 0x34))
    @assert(hasByte(0x12345678, 0x56))
    @assert(hasByte(0x12345678, 0x78))
    @assert(!hasByte(0x12345678, 0xFF))
    @assert(!hasByte(0x12345678, 0x00))

    // gcd / lcm
    @assert(gcd(12, 8) == 4)
    @assert(gcd(100, 75) == 25)
    @assert(gcd(17, 13) == 1)     // coprime
    @assert(gcd(0, 5) == 5)
    @assert(gcd(7, 7) == 7)
    @assert(lcm(4, 6) == 12)
    @assert(lcm(3, 7) == 21)
    @assert(lcm(12, 18) == 36)

    // sign
    @assert(sign(42's32) == 1)
    @assert(sign(-7's32) == -1)
    @assert(sign(0's32) == 0)
}

// Test bit intrinsics
#test
{
    // Population count (standard semantics)
    @assert(@bitcountnz(0'u32) == 0)
    @assert(@bitcountnz(1'u32) == 1)
    @assert(@bitcountnz(0xFFFFFFFF'u32) == 32)
    @assert(@bitcountnz(0xAAAAAAAA'u32) == 16)
    @assert(@bitcountnz(0x55555555'u32) == 16)
    @assert(@bitcountnz(0xDEADBEEF'u32) == 24)

    // Leading zeros (counts consecutive zero bits from the most significant bit)
    @assert(@bitcountlz(0'u32) == 32)
    @assert(@bitcountlz(0x80000000'u32) == 0)
    @assert(@bitcountlz(1'u32) == 31)
    @assert(@bitcountlz(0x00010000'u32) == 15)

    // Trailing zeros (counts consecutive zero bits from the least significant bit)
    @assert(@bitcounttz(0'u32) == 32)
    @assert(@bitcounttz(1'u32) == 0)
    @assert(@bitcounttz(2'u32) == 1)
    @assert(@bitcounttz(0x80000000'u32) == 31)
    @assert(@bitcounttz(0x00010000'u32) == 16)

    // Rotate left/right
    @assert(@rol(0x80000001'u32, 1) == 0x00000003'u32)
    @assert(@ror(0x80000001'u32, 1) == 0xC0000000'u32)
    @assert(@rol(@ror(0xDEADBEEF'u32, 13), 13) == 0xDEADBEEF'u32)

    // Byteswap
    @assert(@byteswap(0x01020304'u32) == 0x04030201'u32)
    @assert(@byteswap(0xAABBCCDD'u32) == 0xDDCCBBAA'u32)
    @assert(@byteswap(@byteswap(0xDEADBEEF'u32)) == 0xDEADBEEF'u32)
}

// Integration: full integrity analysis pipeline
#test
{
    const message = "Swag-lang integrity check: 2024-03-15T08:30:00Z"
    let report = analyze(message)

    let bytes = cast(const [..] u8) message
    @assert(report.byteCount == @countof(bytes))
    @assert(report.checksum == Adler32.compute(message))
    @assert(report.reversedFirst == reverse8(cast(u8) 'S'))
    @assert(report.reversedLast == reverse8(cast(u8) 'Z'))
    @assert(report.bitEntropy > 0)

    // Entropy of all-zero bytes would be 0; printable ASCII is always nonzero
    let avgBitsPerByte = report.bitEntropy / cast(u32) report.byteCount
    @assert(avgBitsPerByte >= 3 and avgBitsPerByte <= 6)

    // Empty analysis
    let empty = analyze("")
    @assert(empty.byteCount == 0)
    @assert(empty.checksum == 0)
    @assert(empty.bitEntropy == 0)

    // Two different messages must produce different checksums
    let report2 = analyze("different payload entirely")
    @assert(report.checksum != report2.checksum)

    // Verify the relationship: popcount of reversed byte == popcount of original
    let testBytes = cast(const [..] u8) message
    for b in testBytes
    {
        @assert(@bitcountnz(b) == @bitcountnz(reverse8(b)))
    }
}
