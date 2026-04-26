#global fileprivate

// Real-life example: data integrity toolkit combining Adler-32 checksums with
// bit manipulation utilities. Exercises struct+impl, const lookup tables,
// bitwise operations, overloads, slices, and integer tricks from std/core.

// ---- Bit reversal (from std/core math/bits.swg) ----------------------------

const Rev8Arr: [256] u8 = [
    0x00, 0x80, 0x40, 0xc0, 0x20, 0xa0, 0x60, 0xe0, 0x10, 0x90, 0x50, 0xd0, 0x30, 0xb0, 0x70, 0xf0,
    0x08, 0x88, 0x48, 0xc8, 0x28, 0xa8, 0x68, 0xe8, 0x18, 0x98, 0x58, 0xd8, 0x38, 0xb8, 0x78, 0xf8,
    0x04, 0x84, 0x44, 0xc4, 0x24, 0xa4, 0x64, 0xe4, 0x14, 0x94, 0x54, 0xd4, 0x34, 0xb4, 0x74, 0xf4,
    0x0c, 0x8c, 0x4c, 0xcc, 0x2c, 0xac, 0x6c, 0xec, 0x1c, 0x9c, 0x5c, 0xdc, 0x3c, 0xbc, 0x7c, 0xfc,
    0x02, 0x82, 0x42, 0xc2, 0x22, 0xa2, 0x62, 0xe2, 0x12, 0x92, 0x52, 0xd2, 0x32, 0xb2, 0x72, 0xf2,
    0x0a, 0x8a, 0x4a, 0xca, 0x2a, 0xaa, 0x6a, 0xea, 0x1a, 0x9a, 0x5a, 0xda, 0x3a, 0xba, 0x7a, 0xfa,
    0x06, 0x86, 0x46, 0xc6, 0x26, 0xa6, 0x66, 0xe6, 0x16, 0x96, 0x56, 0xd6, 0x36, 0xb6, 0x76, 0xf6,
    0x0e, 0x8e, 0x4e, 0xce, 0x2e, 0xae, 0x6e, 0xee, 0x1e, 0x9e, 0x5e, 0xde, 0x3e, 0xbe, 0x7e, 0xfe,
    0x01, 0x81, 0x41, 0xc1, 0x21, 0xa1, 0x61, 0xe1, 0x11, 0x91, 0x51, 0xd1, 0x31, 0xb1, 0x71, 0xf1,
    0x09, 0x89, 0x49, 0xc9, 0x29, 0xa9, 0x69, 0xe9, 0x19, 0x99, 0x59, 0xd9, 0x39, 0xb9, 0x79, 0xf9,
    0x05, 0x85, 0x45, 0xc5, 0x25, 0xa5, 0x65, 0xe5, 0x15, 0x95, 0x55, 0xd5, 0x35, 0xb5, 0x75, 0xf5,
    0x0d, 0x8d, 0x4d, 0xcd, 0x2d, 0xad, 0x6d, 0xed, 0x1d, 0x9d, 0x5d, 0xdd, 0x3d, 0xbd, 0x7d, 0xfd,
    0x03, 0x83, 0x43, 0xc3, 0x23, 0xa3, 0x63, 0xe3, 0x13, 0x93, 0x53, 0xd3, 0x33, 0xb3, 0x73, 0xf3,
    0x0b, 0x8b, 0x4b, 0xcb, 0x2b, 0xab, 0x6b, 0xeb, 0x1b, 0x9b, 0x5b, 0xdb, 0x3b, 0xbb, 0x7b, 0xfb,
    0x07, 0x87, 0x47, 0xc7, 0x27, 0xa7, 0x67, 0xe7, 0x17, 0x97, 0x57, 0xd7, 0x37, 0xb7, 0x77, 0xf7,
    0x0f, 0x8f, 0x4f, 0xcf, 0x2f, 0xaf, 0x6f, 0xef, 0x1f, 0x9f, 0x5f, 0xdf, 0x3f, 0xbf, 0x7f, 0xff]

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
    const m2 = 0x0f0f0f0f'u32
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
        var s1 = .adler & 0xffff
        var s2 = (.adler >> 16) & 0xffff

        let count = @countof(buffer)
        if !count do
            return

        let input = @dataof(buffer)
        if count == 1
        {
            s1 += cast(u32) input[0]
            if s1 >= Base do
                s1 -= Base
            s2 += s1
            if s2 >= Base do
                s2 -= Base
        }
        elif count < 16
        {
            foreach b in buffer
            {
                s1 += cast(u32) b
                s2 += s1
            }

            if s1 >= Base do
                s1 -= Base
            s2 %= Base
        }
        else
        {
            const n = NMax / 16
            var i = 0'u64

            while i + NMax <= count
            {
                for rounds in n
                {
                    for j in 16'u64
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
                    for j in 16'u64
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
                    i += 1
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
    report.reversedLast = reverse8(ptr[report.byteCount - 1])

    var i = 0'u64
    while i + 4 <= report.byteCount
    {
        let word = cast(u32) ptr[i] |
                   cast(u32) ptr[i + 1] << 8 |
                   cast(u32) ptr[i + 2] << 16 |
                   cast(u32) ptr[i + 3] << 24
        if hasZeroByte(word) do
            report.zeroBytesFound += 1
        i += 4
    }

    foreach b in data do
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
    @assert(reverse8(0xA5) == 0xA5)  // 10100101 is a palindrome

    // Double-reverse is identity
    for i in 256
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
    for i in 32'u32
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
    @assert(gcd(17, 13) == 1)    // coprime
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
    foreach b in testBytes
    {
        @assert(@bitcountnz(b) == @bitcountnz(reverse8(b)))
    }
}
