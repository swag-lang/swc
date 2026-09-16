#global private

#[Swag.NoInline]
func byte64(p: [*]s8, i: u64)->s64 => p[i]
#[Swag.NoInline]
func byte32(p: [*]s8, i: u64)->s32 => p[i]
#[Swag.NoInline]
func word64(p: [*]s16, i: u64)->s64 => p[i]
#[Swag.NoInline]
func word32(p: [*]s16, i: u64)->s32 => p[i]
#[Swag.NoInline]
func offset(p: [*]s16, i: u64)->s64 => p[i + 65]
#[Swag.NoInline]
func shared(p: [*]s16, i: u64)->s64
{
    let value = p[i]
    return cast(s64) value + cast(s64) (value < 0 ? -1 : 1)
}
#[Swag.NoInline]
func stored(p: [*]s16, i: u64)->s64
{
    let value = p[i]
    p[i] = 19
    return value
}
#[Swag.NoInline]
func sum(p: [*]s8, count: u64)->s64
{
    var result = 0's64
    for i in 0 until count do result += p[i]
    return result
}

#test
{
    var bytes = [-128's8, -1, 0, 1, 127]
    var words = [-32768's16, -1, 0, 1, 32767]
    var displaced: [70]s16
    for i in 5'u64
    {
        Swag.assert(byte64(&bytes[0], i) == bytes[i])
        Swag.assert(byte32(&bytes[0], i) == bytes[i])
        Swag.assert(word64(&words[0], i) == words[i])
        Swag.assert(word32(&words[0], i) == words[i])
        displaced[i + 65] = words[i]
        Swag.assert(offset(&displaced[0], i) == words[i])
        Swag.assert(shared(&words[0], i) == cast(s64) words[i] + (words[i] < 0 ? -1 : 1))
        let before = words[i]
        Swag.assert(stored(&words[0], i) == before)
        Swag.assert(words[i] == 19)
    }
    Swag.assert(sum(&bytes[0], 0) == 0)
    Swag.assert(sum(&bytes[0], 5) == -1)
}
