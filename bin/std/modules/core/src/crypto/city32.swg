// @LICENCE: MIT
// @ORIGIN: CityHash by Geoff Pike and Jyrki Alakuijala, https://github.com/google/cityhash
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#cityhash

#global namespace Hash

// Provides one-shot CityHash32 computation.
public struct City32
{
    internal currentValue: u32
}

impl City32
{
    const C1 = 0xCC9E2D51
    const C2 = 0x1B873593
    func fetch(buf: const [*] u8) => Math.littleEndianToNative(buf[as u32])

    #[Swag.Safety(.Overflow, false)]
    mtd len0to4(data: const [..] u8)
    {
        var b = .currentValue
        var c = 9'u32
        for v in data
        {
            b = b * C1 + v
            c ^= b
        }

        .currentValue = murmur3(murmur3(b, murmur3(cast(u32) @countof(data), c)))
    }

    #[Swag.Safety(.Overflow, false)]
    mtd len5to12(data: const [..] u8)
    {
        let s   = @dataof(data)
        let len = cast(u32) @countof(data)
        var a   = len + .currentValue
        var b   = len * 5
        var c   = 9'u32
        let d   = b
        a             += fetch(s)
        b             += fetch(s + len - 4)
        c             += fetch(s + ((len >> 1) & 4))
        .currentValue = murmur3(murmur3(c, murmur3(b, murmur3(a, d))))
    }

    #[Swag.Safety(.Overflow, false)]
    mtd len13to24(data: const [..] u8)
    {
        let s   = @dataof(data)
        let len = cast(u32) @countof(data)
        let a   = fetch(s - 4 + (len >> 1))
        let b   = fetch(s + 4)
        let c   = fetch(s + len - 8)
        let d   = fetch(s + (len >> 1))
        let e   = fetch(s)
        let f   = fetch(s + len - 4)
        let h   = .currentValue + len
        .currentValue = murmur3(murmur3(f, murmur3(e, murmur3(d, murmur3(c, murmur3(b, murmur3(a, h)))))))
    }

    mtd reset(seed: u32)
    {
        .currentValue = seed
    }

    // CityHash32 is not an incremental algorithm. Keep this mutating operation
    // internal so callers cannot mistake successive calls for concatenation.
    #[Swag.Safety(.Overflow, false)]
    mtd update(data: const [..] u8)
    {
        let len = cast(u32) @countof(data)

        switch
        {
        case len <= 4:  return .len0to4(data)
        case len <= 12: return .len5to12(data)
        case len <= 24: return .len13to24(data)
        }

        let seed = .currentValue
        var s    = @dataof(data)
        var h    = len + seed
        var g    = C1 * len

        // len > 24
        var f  = g
        var a0 = Math.ror(fetch(s + len - 4) * C1, 17) * C2
        var a1 = Math.ror(fetch(s + len - 8) * C1, 17) * C2
        var a2 = Math.ror(fetch(s + len - 16) * C1, 17) * C2
        var a3 = Math.ror(fetch(s + len - 12) * C1, 17) * C2
        var a4 = Math.ror(fetch(s + len - 20) * C1, 17) * C2
        h ^= a0
        h = Math.ror(h, 19)
        h = h * 5 + 0xE6546B64
        h ^= a2
        h = Math.ror(h, 19)
        h = h * 5 + 0xE6546B64
        g ^= a1
        g = Math.ror(g, 19)
        g = g * 5 + 0xE6546B64
        g ^= a3
        g = Math.ror(g, 19)
        g = g * 5 + 0xE6546B64
        f += a4
        f = Math.ror(f, 19)
        f = f * 5 + 0xE6546B64

        for (len - 1) / 20
        {
            a0 = Math.ror(fetch(s) * C1, 17) * C2
            a1 = fetch(s + 4)
            a2 = Math.ror(fetch(s + 8) * C1, 17) * C2
            a3 = Math.ror(fetch(s + 12) * C1, 17) * C2
            a4 = fetch(s + 16)
            h  ^= a0
            h  = Math.ror(h, 18)
            h  = h * 5 + 0xE6546B64
            f  += a1
            f  = Math.ror(f, 19)
            f  = f * C1
            g  += a2
            g  = Math.ror(g, 18)
            g  = g * 5 + 0xE6546B64
            h  ^= a3 + a1
            h  = Math.ror(h, 19)
            h  = h * 5 + 0xE6546B64
            g  ^= a4
            g  = Math.byteswap(g) * 5
            h  += a4 * 5
            h  = Math.byteswap(h)
            f  += a0
            swap(&f, &h)
            swap(&f, &g)
            s += 20
        }

        g             = Math.ror(g, 11) * C1
        g             = Math.ror(g, 17) * C1
        f             = Math.ror(f, 11) * C1
        f             = Math.ror(f, 17) * C1
        h             = Math.ror(h + g, 19)
        h             = h * 5 + 0xE6546B64
        h             = Math.ror(h, 17) * C1
        h             = Math.ror(h + f, 19)
        h             = h * 5 + 0xE6546B64
        h             = Math.ror(h, 17) * C1
        .currentValue = h
    }

    // Computes CityHash32 for `buffer`, optionally mixed with `seed`.
    #[Swag.ConstExpr]
    public func compute(buffer: const [..] u8, seed: u32 = 0)->u32
    {
        var v: City32
        v.reset(seed)
        v.update(buffer)
        return v.currentValue
    }
}
