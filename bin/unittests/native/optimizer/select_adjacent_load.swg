#global private

#[Swag.NoInline]
func select64(values: [*] u64, condition: u64)->u64 => condition != 0 ? values[0] : values[1]

#[Swag.NoInline]
func select64Reverse(values: [*] u64, condition: u64)->u64 => condition != 0 ? values[1] : values[0]

#[Swag.NoInline]
func select32Offset(values: [*] u32, condition: u64)->u32 => condition == 0 ? values[4] : values[5]

#[Swag.NoInline]
func select8(values: [*] u8, condition: u64)->u8 => condition != 0 ? values[0] : values[1]

#test
{
    var values64 = [11'u64, 22]
    var values32 = [1'u32, 2, 3, 4, 55, 66]
    var values8  = [77'u8, 88]
    for condition in [0'u64, 1, 7, 0xFFFFFFFFFFFFFFFF]
    {
        Swag.assert(select64(&values64[0], condition) == (condition != 0 ? 11 : 22))
        Swag.assert(select64Reverse(&values64[0], condition) == (condition != 0 ? 22 : 11))
        Swag.assert(select32Offset(&values32[0], condition) == (condition == 0 ? 55 : 66))
        Swag.assert(select8(&values8[0], condition) == (condition != 0 ? 77 : 88))
    }
}
