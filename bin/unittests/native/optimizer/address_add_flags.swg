#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func unsignedChoice(a, b, c: u64)->u64 => a < b ? c + c : c + 1
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedChoice(a, b, c: s64)->s64 => a < b ? c + c : c + 1
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func narrowChoice(a, b, c: u32)->u32 => a < b ? c + c : c + 1
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func chain(a, b, c: u64)->u64
{
    var total = a + b
    for i in 7 do total = (total + c) ^ i
    return total
}

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            for c in values
            {
                let result = unsignedChoice(a, b, c)
                if a < b do Swag.assert(result == c + c)
                else do Swag.assert(result == c + 1)
                let a32      = cast(u32) (a & 0xFFFFFFFF)
                let b32      = cast(u32) (b & 0xFFFFFFFF)
                let c32      = cast(u32) (c & 0xFFFFFFFF)
                let result32 = narrowChoice(a32, b32, c32)
                if a32 < b32 do Swag.assert(result32 == c32 + c32)
                else do Swag.assert(result32 == c32 + 1)
                var expected = a + b
                for i in 7 do expected = (expected + c) ^ i
                Swag.assert(chain(a, b, c) == expected)
            }
        }
    }
    Swag.assert(signedChoice(-1, 0, -5) == -10)
    Swag.assert(signedChoice(0, -1, -5) == -4)
}
