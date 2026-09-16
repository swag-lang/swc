#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// Byte and word values chosen between two paths are moved at 32 bits when
// nothing reads past their width. The upper bits they no longer keep must
// never show: every byte result is read back at full width, and a byte
// written into a register holding a wider value keeps that value's upper bits.

#[Swag.Optimize(true), Swag.NoInline]
func saturatedAdd(a, b: u8)->u8
{
    let s = cast(u32) a + cast(u32) b
    return s > 255 ? 255 : cast(u8) s
}

#[Swag.Optimize(true), Swag.NoInline]
func lower(c: u8)->u8 => (c >= 'A' and c <= 'Z') ? c + 32 : c

#[Swag.Optimize(true), Swag.NoInline]
func pickWord(flag: bool, a, b: u16)->u32 => cast(u32) (flag ? a : b) + 1

#[Swag.Optimize(true), Swag.NoInline]
func keepUpper(wide: u64, low: u8)->u64
{
    var v = wide
    v = (v & ~0xFF'u64) | cast(u64) low
    return v
}

#[Swag.Optimize(true), Swag.NoInline]
func byteSum(p: const [*] u8, n: u64)->u32
{
    var total = 0'u32
    for i in n
    {
        let c = p[i] > 127 ? 127'u8 : p[i]
        total += cast(u32) c
    }
    return total
}

#test
{
    Swag.assert(saturatedAdd(200, 100) == 255)
    Swag.assert(saturatedAdd(20, 100) == 120)
    Swag.assert(saturatedAdd(255, 0) == 255)
    Swag.assert(lower('Q') == 'q' and lower('a') == 'a' and lower('@') == '@' and lower('[') == '[')
    Swag.assert(pickWord(true, 0xFFFF, 3) == 0x10000)
    Swag.assert(pickWord(false, 0xFFFF, 3) == 4)
    Swag.assert(keepUpper(0x1122334455667788, 0x99) == 0x1122334455667799)

    var bytes: [4] u8 = [10, 200, 127, 128]
    Swag.assert(byteSum(&bytes[0], 4) == 10 + 127 + 127 + 127)
}
