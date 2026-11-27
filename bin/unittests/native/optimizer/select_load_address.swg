#global private

#[Swag.NoInline]
func selectBase(left, right: [*] u64, condition: u64)->u64 => condition != 0 ? left[0] : right[0]

#[Swag.NoInline]
func selectIndex(values: [*] u64, left, right, condition: u64)->u64 => condition != 0 ? values[left] : values[right]

#test
{
    var left   = [11_u64]
    var right  = [22_u64]
    var values = [31_u64, 32, 33, 34, 35]
    for condition in [0_u64, 1, 9, 0xFFFFFFFFFFFFFFFF]
    {
        Swag.require(selectBase(&left[0], &right[0], condition) == (condition != 0 ? 11 : 22))
        Swag.require(selectIndex(&values[0], 1, 4, condition) == (condition != 0 ? 32 : 35))
    }
}
