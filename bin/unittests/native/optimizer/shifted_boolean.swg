#global private

#[Swag.NoInline]
func shiftThree(value: u64)->u64 => cast(u64)(value == 0) << 3

#[Swag.NoInline]
func shiftThirtyOne(value: u64)->u64 => cast(u64)(value != 0) << 31

#test
{
    for value in [0'u64, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    {
        Swag.assert(shiftThree(value) == cast(u64)(value == 0) << 3)
        Swag.assert(shiftThirtyOne(value) == cast(u64)(value != 0) << 31)
    }
}
