#global namespace Hash
#global #[Swag.Safety(.Overflow, false)]

internal func addInputLength(count: *[2] u32, length: u64)
{
    let lowBits = cast(u32, length << 3)
    count[][0] += lowBits
    if count[][0] < lowBits do
        count[][1] += 1
    count[][1] += cast(u32, length >> 29)
}

// Computes an MD5 digest incrementally.
//
// MD5 is suitable for compatibility and non-adversarial checksums only. Do not
// use it for passwords, signatures, or other security-sensitive verification.
public struct Md5
{
    internal
    {
        state:  [4] u32 = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476]
        count:  [2] u32
        buffer: [64] u8
    }
}

public impl Md5
{
    // Holds a 128-bit MD5 digest.
    alias Digest = [16] u8

    // Finalizes the current sequence and returns its 128-bit digest.
    //
    // Call [[reset]] before reusing this value after finalization.
    mtd finalize()->Digest
    {
        var digest:  #returntype
        var bits:    [8] u8
        var padding: [64] u8
        padding[0] = 0x80
        encode(&bits[0], .count, 8)

        let index  = (.count[0] >> 3) & 0x3F
        let padLen = (index < 56) ? (56 - index) : (120 - index)

        .update(padding[until padLen])
        .update(bits)
        encode(&digest[0], .state, 16)
        return digest
    }

    // Resets the sequence to the standard MD5 initial state.
    mtd reset()
    {
        Swag.init(me, 1)
    }

    // Includes `data` in the running digest.
    mtd update(data: const [..] u8)
    {
        let input    = data.buffer
        let inputLen = data.count

        var index = (.count[0] >> 3) & 0x3F
        addInputLength(&.count, inputLen)

        var i       = 0'u64
        let partLen = 64 - index
        if inputLen >= partLen
        {
            Memory.copy(&.buffer[index], input, cast(u64, partLen))
            transform(.state, &.buffer[0])
            i = partLen
            while inputLen - i >= 64
            {
                transform(.state, input + i)
                i += 64
            }

            index = 0
        }

        Memory.copy(&.buffer[index], input + i, inputLen - i)
    }

    // Computes the MD5 digest of `buffer` in one operation.
    func compute(buffer: const [..] u8)->Digest
    {
        let bufferLen = buffer.count
        if bufferLen < 56
        {
            // Short buffers fit in a single MD5 block, so skip the generic update/final pipeline.
            var state: [4] u32 = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476]
            var block: [64] u8

            if bufferLen do
                Memory.copy(&block[0], buffer.buffer, bufferLen)

            block[bufferLen] = 0x80

            let bitCount = cast([*] u64, block.buffer + 56)
            bitCount[0] = Math.nativeToLittleEndian(bufferLen << 3)

            transform(state, &block[0])

            var result: #returntype
            encode(&result[0], state, 16)
            return result
        }

        var v: Md5
        v.reset()
        v.update(buffer)
        return v.finalize()
    }

    // Formats `digest` as 32 uppercase hexadecimal digits.
    func toString(digest: Digest)->String
    {
        const CONV = "0123456789ABCDEF"

        var result: #returntype
        result.reserve(33)

        for v in digest
        {
            result += CONV[v >> 4]
            result += CONV[v & 0x0F]
        }

        return result
    }
}

impl Md5
{
    #[Swag.Inline]
    func f1(x, y, z: u32)->u32 => (x & y) | (~x & z)

    #[Swag.Inline]
    func f2(x, y, z: u32)->u32 => (x & z) | (y & ~z)

    #[Swag.Inline]
    func f3(x, y, z: u32)->u32 => x ^ (y ^ z)

    #[Swag.Inline]
    func f4(x, y, z: u32)->u32 => y ^ (x | ~z)

    #[Swag.Inline]
    func ff1(a, b, c, d, x: u32, shift: u8, constant: u32)->u32 => b + Math.rol(a + f1(b, c, d) + x + constant, shift)

    #[Swag.Inline]
    func ff2(a, b, c, d, x: u32, shift: u8, constant: u32)->u32 => b + Math.rol(a + f2(b, c, d) + x + constant, shift)

    #[Swag.Inline]
    func ff3(a, b, c, d, x: u32, shift: u8, constant: u32)->u32 => b + Math.rol(a + f3(b, c, d) + x + constant, shift)

    #[Swag.Inline]
    func ff4(a, b, c, d, x: u32, shift: u8, constant: u32)->u32 => b + Math.rol(a + f4(b, c, d) + x + constant, shift)

    func transform(state: [4] u32, block: const [*] u8)
    {
        var a     = state[0]
        var b     = state[1]
        var c     = state[2]
        var d     = state[3]
        let words = cast(const [*] u32, block)
        var x: [16] u32
        for index in x.count do
            x[index] = Math.littleEndianToNative(words[index])

        // Round 1
        a = ff1(a, b, c, d, x[0], 7, 0xD76AA478)       // 1
        d = ff1(d, a, b, c, x[1], 12, 0xE8C7B756)      // 2
        c = ff1(c, d, a, b, x[2], 17, 0x242070DB)      // 3
        b = ff1(b, c, d, a, x[3], 22, 0xC1BDCEEE)      // 4
        a = ff1(a, b, c, d, x[4], 7, 0xF57C0FAF)       // 5
        d = ff1(d, a, b, c, x[5], 12, 0x4787C62A)      // 6
        c = ff1(c, d, a, b, x[6], 17, 0xA8304613)      // 7
        b = ff1(b, c, d, a, x[7], 22, 0xFD469501)      // 8
        a = ff1(a, b, c, d, x[8], 7, 0x698098D8)       // 9
        d = ff1(d, a, b, c, x[9], 12, 0x8B44F7AF)      // 10
        c = ff1(c, d, a, b, x[10], 17, 0xFFFF5BB1)     // 11
        b = ff1(b, c, d, a, x[11], 22, 0x895CD7BE)     // 12
        a = ff1(a, b, c, d, x[12], 7, 0x6B901122)      // 13
        d = ff1(d, a, b, c, x[13], 12, 0xFD987193)     // 14
        c = ff1(c, d, a, b, x[14], 17, 0xA679438E)     // 15
        b = ff1(b, c, d, a, x[15], 22, 0x49B40821)     // 16

        // Round 2
        a = ff2(a, b, c, d, x[1], 5, 0xF61E2562)       // 17
        d = ff2(d, a, b, c, x[6], 9, 0xC040B340)       // 18
        c = ff2(c, d, a, b, x[11], 14, 0x265E5A51)     // 19
        b = ff2(b, c, d, a, x[0], 20, 0xE9B6C7AA)      // 20
        a = ff2(a, b, c, d, x[5], 5, 0xD62F105D)       // 21
        d = ff2(d, a, b, c, x[10], 9, 0x2441453)       // 22
        c = ff2(c, d, a, b, x[15], 14, 0xD8A1E681)     // 23
        b = ff2(b, c, d, a, x[4], 20, 0xE7D3FBC8)      // 24
        a = ff2(a, b, c, d, x[9], 5, 0x21E1CDE6)       // 25
        d = ff2(d, a, b, c, x[14], 9, 0xC33707D6)      // 26
        c = ff2(c, d, a, b, x[3], 14, 0xF4D50D87)      // 27

        b = ff2(b, c, d, a, x[8], 20, 0x455A14ED)      // 28
        a = ff2(a, b, c, d, x[13], 5, 0xA9E3E905)      // 29
        d = ff2(d, a, b, c, x[2], 9, 0xFCEFA3F8)       // 30
        c = ff2(c, d, a, b, x[7], 14, 0x676F02D9)      // 31
        b = ff2(b, c, d, a, x[12], 20, 0x8D2A4C8A)     // 32

        // Round 3
        a = ff3(a, b, c, d, x[5], 4, 0xFFFA3942)       // 33
        d = ff3(d, a, b, c, x[8], 11, 0x8771F681)      // 34
        c = ff3(c, d, a, b, x[11], 16, 0x6D9D6122)     // 35
        b = ff3(b, c, d, a, x[14], 23, 0xFDE5380C)     // 36
        a = ff3(a, b, c, d, x[1], 4, 0xA4BEEA44)       // 37
        d = ff3(d, a, b, c, x[4], 11, 0x4BDECFA9)      // 38
        c = ff3(c, d, a, b, x[7], 16, 0xF6BB4B60)      // 39
        b = ff3(b, c, d, a, x[10], 23, 0xBEBFBC70)     // 40
        a = ff3(a, b, c, d, x[13], 4, 0x289B7EC6)      // 41
        d = ff3(d, a, b, c, x[0], 11, 0xEAA127FA)      // 42
        c = ff3(c, d, a, b, x[3], 16, 0xD4EF3085)      // 43
        b = ff3(b, c, d, a, x[6], 23, 0x4881D05)       // 44
        a = ff3(a, b, c, d, x[9], 4, 0xD9D4D039)       // 45
        d = ff3(d, a, b, c, x[12], 11, 0xE6DB99E5)     // 46
        c = ff3(c, d, a, b, x[15], 16, 0x1FA27CF8)     // 47
        b = ff3(b, c, d, a, x[2], 23, 0xC4AC5665)      // 48

        // Round 4
        a = ff4(a, b, c, d, x[0], 6, 0xF4292244)       // 49
        d = ff4(d, a, b, c, x[7], 10, 0x432AFF97)      // 50
        c = ff4(c, d, a, b, x[14], 15, 0xAB9423A7)     // 51
        b = ff4(b, c, d, a, x[5], 21, 0xFC93A039)      // 52
        a = ff4(a, b, c, d, x[12], 6, 0x655B59C3)      // 53
        d = ff4(d, a, b, c, x[3], 10, 0x8F0CCC92)      // 54
        c = ff4(c, d, a, b, x[10], 15, 0xFFEFF47D)     // 55
        b = ff4(b, c, d, a, x[1], 21, 0x85845DD1)      // 56
        a = ff4(a, b, c, d, x[8], 6, 0x6FA87E4F)       // 57
        d = ff4(d, a, b, c, x[15], 10, 0xFE2CE6E0)     // 58
        c = ff4(c, d, a, b, x[6], 15, 0xA3014314)      // 59
        b = ff4(b, c, d, a, x[13], 21, 0x4E0811A1)     // 60
        a = ff4(a, b, c, d, x[4], 6, 0xF7537E82)       // 61
        d = ff4(d, a, b, c, x[11], 10, 0xBD3AF235)     // 62
        c = ff4(c, d, a, b, x[2], 15, 0x2AD7D2BB)      // 63
        b = ff4(b, c, d, a, x[9], 21, 0xEB86D391)      // 64

        state[0] += a
        state[1] += b
        state[2] += c
        state[3] += d
    }

    func encode(output: [*] u8, input: const [*] u32, len: u32)
    {
        let words = cast([*] u32, output)
        for index in len / 4 do
            words[index] = Math.nativeToLittleEndian(input[index])
    }
}
