#global private

#[Swag.NoInline]
func remainder64_1(a: s64)->s64 => a % 1
#[Swag.NoInline]
func remainder64_2(a: s64)->s64 => a % 2
#[Swag.NoInline]
func remainder64_4(a: s64)->s64 => a % 4
#[Swag.NoInline]
func remainder64_8(a: s64)->s64 => a % 8
#[Swag.NoInline]
func remainder64_128(a: s64)->s64 => a % 128
#[Swag.NoInline]
func remainder64_65536(a: s64)->s64 => a % 65536
#[Swag.NoInline]
func remainder64_2147483648(a: s64)->s64 => a % 2147483648
#[Swag.NoInline]
func remainder64_4611686018427387904(a: s64)->s64 => a % 4611686018427387904
#[Swag.NoInline]
func dynamic64(a, b: s64)->s64 => a % b
#[Swag.NoInline]
func reused64(a: s64)->s64 => (a % 8) ^ a

#[Swag.NoInline]
func remainder32_1(a: s32)->s32 => a % 1
#[Swag.NoInline]
func remainder32_2(a: s32)->s32 => a % 2
#[Swag.NoInline]
func remainder32_4(a: s32)->s32 => a % 4
#[Swag.NoInline]
func remainder32_8(a: s32)->s32 => a % 8
#[Swag.NoInline]
func remainder32_128(a: s32)->s32 => a % 128
#[Swag.NoInline]
func remainder32_65536(a: s32)->s32 => a % 65536
#[Swag.NoInline]
func remainder32_1073741824(a: s32)->s32 => a % 1073741824
#[Swag.NoInline]
func dynamic32(a, b: s32)->s32 => a % b
#[Swag.NoInline]
func reused32(a: s32)->s32 => (a % 8) ^ a

#test
{
    let values64 = [-9223372036854775808's64, -9223372036854775807, -65537, -65536, -65535, -129, -128, -127, -9, -8, -7, -2, -1, 0, 1, 2, 7, 8, 9, 127, 128, 129, 65535, 65536, 65537, 9223372036854775807]
    for a in values64
    {
        Swag.assert(remainder64_1(a) == dynamic64(a, 1))
        Swag.assert(remainder64_2(a) == dynamic64(a, 2))
        Swag.assert(remainder64_4(a) == dynamic64(a, 4))
        Swag.assert(remainder64_8(a) == dynamic64(a, 8))
        Swag.assert(remainder64_128(a) == dynamic64(a, 128))
        Swag.assert(remainder64_65536(a) == dynamic64(a, 65536))
        Swag.assert(remainder64_2147483648(a) == dynamic64(a, 2147483648))
        Swag.assert(remainder64_4611686018427387904(a) == dynamic64(a, 4611686018427387904))
        Swag.assert(reused64(a) == (dynamic64(a, 8) ^ a))
    }
    let values32 = [-2147483648's32, -2147483647, -65537, -65536, -65535, -129, -128, -127, -9, -8, -7, -2, -1, 0, 1, 2, 7, 8, 9, 127, 128, 129, 65535, 65536, 65537, 2147483647]
    for a in values32
    {
        Swag.assert(remainder32_1(a) == dynamic32(a, 1))
        Swag.assert(remainder32_2(a) == dynamic32(a, 2))
        Swag.assert(remainder32_4(a) == dynamic32(a, 4))
        Swag.assert(remainder32_8(a) == dynamic32(a, 8))
        Swag.assert(remainder32_128(a) == dynamic32(a, 128))
        Swag.assert(remainder32_65536(a) == dynamic32(a, 65536))
        Swag.assert(remainder32_1073741824(a) == dynamic32(a, 1073741824))
        Swag.assert(reused32(a) == (dynamic32(a, 8) ^ a))
    }
}
