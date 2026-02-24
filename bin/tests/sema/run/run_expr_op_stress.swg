#global internal

enum StressKind: u16
{
    A = 3
    B = 9
    C = 42
}

#test
{
    func stressMixed()->s32
    {
        var a: s32 = 120
        var b: s32 = 7

        a += b
        a *= 2
        a -= 10
        a /= 3
        a %= 50

        b <<= 3
        b >>= 1
        b |= 6
        b ^= 8
        b &= 31

        if a < b or b == 0
        {
            a += 100
        }
        else
        {
            a += b
        }

        var f: f32 = 3.5'f32
        f *= 2.0'f32
        f += 1.0'f32
        f /= 2.0'f32
        f -= 1.0'f32

        var g: f64 = 10.0'f64
        g += cast(f64) f
        g -= 1.0'f64
        g *= 2.0'f64
        g /= 3.0'f64

        var p: *void = null
        if p == null
        {
            p = cast(*void) 0x10'u64
        }

        if p != null and a > 0
        {
            a += 5
        }

        var h: u32 = cast(u32) a
        h <<= 1'u32
        h >>= 2'u32
        h |= 0x20'u32
        h ^= 0x03'u32
        h &= 0x3F'u32

        return cast(s32) h + cast(s32) g + b
    }

    const V = #run stressMixed()
    #assert(#typeof(V) == s32)
    #assert(V == 92)
}

#test
{
    func stressEnumAndWidths()->s64
    {
        var k: StressKind = StressKind.A
        k = StressKind.C

        var a: s8 = -10's8
        var b: u16 = 300'u16
        var c: s64 = cast(s64) a + cast(s64) b + cast(s64) cast(u16) k

        c <<= 1
        c >>= 2

        var d: u64 = 1000'u64
        d %= 331'u64
        d |= 40'u64
        d ^= 5'u64

        c += cast(s64) d
        return c
    }

    const V = #run stressEnumAndWidths()
    #assert(#typeof(V) == s64)
    #assert(V == 208's64)
}

#test
{
    func stressHelper(a: s32, b: s32)->s32
    {
        return a * b + b - a
    }

    func stressCallAndIndex()->s32
    {
        var arr: [4] s32 = [3, 5, 7, 11]
        var idx: s32 = 1
        var acc: s32 = 0

        acc += stressHelper(arr[0], arr[idx])
        idx += 1
        acc += stressHelper(arr[idx], arr[3])
        acc += arr[0] << 2
        acc -= arr[1] >> 1

        if acc >= 100 and acc != 109
        {
            acc += 1
        }

        return acc
    }

    const V = #run stressCallAndIndex()
    #assert(#typeof(V) == s32)
    #assert(V == 109)
}
