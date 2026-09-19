#global private

// Arguments read from memory load straight into their lanes. Bytes, words,
// dwords, qwords and floats read through several addresses in one call,
// addresses that are themselves other arguments, and loops must pass the
// values the memory holds.

struct Sample
{
    tag:    u8
    delta:  s16
    count:  s32
    total:  u64
    weight: f32
}

#[Swag.NoInline]
func mixFour(a: u8, b: s16, c: s32, d: u64)->s64 => cast(s64) a * 1000000 + cast(s64) b * 1000 + cast(s64) c + cast #wrap (s64) d

#[Swag.NoInline]
func mixFloat(a: f32, b: u8, c: f32, d: s32)->f32 => a * 2 + cast(f32) b + c * 3 + cast(f32) d

#[Swag.NoInline]
func pick(p: const [*] u8, index: u64)->u8 => p[index]

#[Swag.Optimize(true), Swag.NoInline]
func passFields(s: const *Sample)->s64 => mixFour(s.tag, s.delta, s.count, s.total)

#[Swag.Optimize(true), Swag.NoInline]
func passElements(bytes: const [*] u8, words: const [*] s16, i, j: u64)->s64
{
    var dwords: [2] s32 = [-7, 70000]
    var qwords: [2] u64 = [5, 0xFFFFFFFF]
    return mixFour(bytes[i], words[j], dwords[i & 1], qwords[j & 1])
}

#[Swag.Optimize(true), Swag.NoInline]
func passFloats(s, t: const *Sample)->f32 => mixFloat(s.weight, t.tag, t.weight, s.count)

#[Swag.Optimize(true), Swag.NoInline]
func sumPicked(p: const [*] u8, n: u64)->u32
{
    var total = 0'u32
    for i in n do
        total += cast(u32) pick(p, cast(u64) p[i])
    return total
}

#test
{
    let first  = Sample{tag: 200, delta: -300, count: -45678, total: 99, weight: 1.5}
    let second = Sample{tag: 7, delta: 12, count: 34, total: 0xFFFFFFFFFFFFFFFF, weight: -0.25}
    Swag.assert(passFields(&first) == 200_000_000 - 300_000 - 45678 + 99)
    Swag.assert(passFields(&second) == 7_000_000 + 12_000 + 34 - 1)
    Swag.assert(passFloats(&first, &second) == 1.5 * 2 + 7 - 0.25 * 3 - 45678)

    var bytes: [4] u8  = [255, 1, 2, 3]
    var words: [3] s16 = [-32768, 32767, -1]
    Swag.assert(passElements(&bytes[0], &words[0], 0, 0) == 255_000_000 - 32_768_000 - 7 + 5)
    Swag.assert(passElements(&bytes[0], &words[0], 1, 1) == 4_328_804_295's64)
    Swag.assert(passElements(&bytes[0], &words[0], 3, 2) == 3_000_000 - 1000 + 70000 + 5)

    var table: [4] u8 = [3, 0, 1, 2]
    Swag.assert(sumPicked(&table[0], 4) == 2 + 3 + 0 + 1)
}
