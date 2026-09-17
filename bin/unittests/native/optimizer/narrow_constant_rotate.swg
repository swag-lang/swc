#global private

// Complementary constant shifts of a byte or a word form a byte or word
// rotate. Every byte and word, both directions, and the halves of a word
// swapped must agree with the rotations computed bit by bit.

#[Swag.Optimize(true), Swag.NoInline]
func swapWord(x: u16)->u16 => cast #wrap (u16) ((x << 8) | (x >> 8))
#[Swag.Optimize(true), Swag.NoInline]
func rotateWordLeft3(x: u16)->u16 => cast #wrap (u16) ((x << 3) | (x >> 13))
#[Swag.Optimize(true), Swag.NoInline]
func rotateByteLeft1(x: u8)->u8 => cast #wrap (u8) ((x << 1) | (x >> 7))
#[Swag.Optimize(true), Swag.NoInline]
func rotateByteRight3(x: u8)->u8 => cast #wrap (u8) ((x >> 3) | (x << 5))
#[Swag.Optimize(true), Swag.NoInline]
func swapWordAt(p: const [*] u16, i: u64)->u32 => cast(u32) swapWord(p[i]) + 1

func slowRotate(x: u64, bits, count: u32)->u64
{
    var result = 0'u64
    for i in bits
    {
        if ((x >> i) & 1) == 1 do
            result |= 1'u64 << ((i + count) % bits)
    }
    return result
}

#test
{
    for i in 0 until 65536
    {
        let x = cast(u16) i
        Swag.assert(cast(u64) swapWord(x) == slowRotate(cast(u64) x, 16, 8))
        Swag.assert(cast(u64) rotateWordLeft3(x) == slowRotate(cast(u64) x, 16, 3))
    }
    for i in 0 until 256
    {
        let x = cast(u8) i
        Swag.assert(cast(u64) rotateByteLeft1(x) == slowRotate(cast(u64) x, 8, 1))
        Swag.assert(cast(u64) rotateByteRight3(x) == slowRotate(cast(u64) x, 8, 5))
    }
    var words: [3] u16 = [0x1234, 0xFF00, 0x00FF]
    Swag.assert(swapWordAt(&words[0], 0) == 0x3413)
    Swag.assert(swapWordAt(&words[0], 1) == 0x0100)
    Swag.assert(swapWordAt(&words[0], 2) == 0xFF01)
}
