#global private

#[Swag.NoInline]
func divide3(a: u64)->u64 => a / 3
#[Swag.NoInline]
func divide7(a: u64)->u64 => a / 7
#[Swag.NoInline]
func divide63(a: u64)->u64 => a / 63
#[Swag.NoInline]
func remainder3(a: u64)->u64 => a % 3
#[Swag.NoInline]
func remainder7(a: u64)->u64 => a % 7
#[Swag.NoInline]
func remainder10(a: u64)->u64 => a % 10
#[Swag.NoInline]
func divide32(a: u32)->u32 => a / 7
#[Swag.NoInline]
func remainder32(a: u32)->u32 => a % 10
#[Swag.NoInline]
func dynamicDivide(a, b: u64)->u64 => a / b
#[Swag.NoInline]
func dynamicRemainder(a, b: u64)->u64 => a % b
#[Swag.NoInline]
func keepInputs(a, b, c, d: u64)->u64 => (a / 7) ^ (b % 10) ^ (c / 63) ^ (d % 3) ^ a ^ b ^ c ^ d

#test
{
    let values = [0'u64, 1, 2, 3, 6, 7, 9, 10, 62, 63, 64, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for value in values
    {
        Swag.assert(divide3(value) == dynamicDivide(value, 3))
        Swag.assert(divide7(value) == dynamicDivide(value, 7))
        Swag.assert(divide63(value) == dynamicDivide(value, 63))
        Swag.assert(remainder3(value) == dynamicRemainder(value, 3))
        Swag.assert(remainder7(value) == dynamicRemainder(value, 7))
        Swag.assert(remainder10(value) == dynamicRemainder(value, 10))
        let narrow = cast(u32) (value & 0xFFFFFFFF)
        Swag.assert(divide32(narrow) == dynamicDivide(narrow, 7))
        Swag.assert(remainder32(narrow) == dynamicRemainder(narrow, 10))
        for other in values
        {
            let expected = dynamicDivide(value, 7) ^ dynamicRemainder(other, 10) ^ dynamicDivide(~value, 63) ^ dynamicRemainder(~other, 3) ^ value ^ other ^ ~value ^ ~other
            Swag.assert(keepInputs(value, other, ~value, ~other) == expected)
        }
    }
}
