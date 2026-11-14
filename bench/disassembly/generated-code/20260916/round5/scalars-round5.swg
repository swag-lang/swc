#global public

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func loadPair(p: [*] u64, a, b: u64)->u64 => p[0] + p[1]

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func loadRepeated(p: [*] u64, a, b: u64)->u64 => p[0] * a + p[0]

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func loadScaled(p: [*] u64, a, b: u64)->u64 => p[a] + b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func loadScaledOffset(p: [*] u64, a, b: u64)->u64 => p[a + 3] + b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func loadNarrow(p: [*] u8, a, b: u64)->u64 => cast(u64) p[a] + b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func loadSigned(p: [*] s16, a: u64, b: s64)->s64 => cast(s64) p[a] + b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func maskedLoad(p: [*] u64, a, b: u64)->u64 => p[0] & 0xFF

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shiftedLoad(p: [*] u64, a, b: u64)->u64 => (p[0] >> 16) & 0xFF

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func selectLoad(p: [*] u64, a, b: u64)->u64 => a != 0 ? p[0] : p[1]

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func loadCompare(p: [*] u64, a, b: u64)->u64 => p[0] < a ? b : 0

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func loadBit(p: [*] u64, a, b: u64)->u64 => (p[0] & 1) != 0 ? a : b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func loadSum4(p: [*] u64, a, b: u64)->u64 => p[0] + p[1] + p[2] + p[3]

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func storeReload(p: [*] u64, a, b: u64)->u64
{
    p[0] = a
    return p[0] + b
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func storeNarrow(p: [*] u8, a, b: u64)->u64
{
    p[0] = cast(u8) (a & 255)
    return cast(u64) p[0] + b
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func updateMemory(p: [*] u64, a, b: u64)->u64
{
    p[0] += a
    return p[0] + b
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func accumulate(p: [*] u64, a, b: u64)->u64
{
    var result = b
    for i in 0 until a do result += p[i]
    return result
}
