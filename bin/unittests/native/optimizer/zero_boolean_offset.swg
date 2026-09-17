#global private

#[Swag.NoInline]
func plusFive64(value: u64)->u64 => cast(u64)(value == 0) + 5

#[Swag.NoInline]
func plus12732(value: u32)->u32 => cast(u32)(value == 0) + 127

#test
{
    for value in [0'u64, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
        do Swag.assert(plusFive64(value) == cast(u64)(value == 0) + 5)

    for value in [0'u32, 1, 0x80000000, 0xFFFFFFFF]
        do Swag.assert(plus12732(value) == cast(u32)(value == 0) + 127)
}
