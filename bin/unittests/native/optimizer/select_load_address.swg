#global private

#[Swag.NoInline]
func selectBase(left, right: [*] u64, condition: u64)->u64 => condition != 0 ? left[0] : right[0]

#[Swag.NoInline]
func selectIndex(values: [*] u64, left, right, condition: u64)->u64 => condition != 0 ? values[left] : values[right]

#test
{
    var left   = [11'u64]
    var right  = [22'u64]
    var values = [31'u64, 32, 33, 34, 35]
    for condition in [0'u64, 1, 9, 0xFFFFFFFFFFFFFFFF]
    {
        Swag.assert(selectBase(&left[0], &right[0], condition) == (condition != 0 ? 11 : 22))
        Swag.assert(selectIndex(&values[0], 1, 4, condition) == (condition != 0 ? 32 : 35))
    }
}
