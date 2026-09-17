#global private

#[Swag.NoInline]
func equal64(values: [*] u64, index, value: u64)->u64 => cast(u64) (values[index] == value)

#[Swag.NoInline]
func notEqual32(values: [*] u32, index: u64, value: u32)->u32 => cast(u32) (values[index] != value)

#[Swag.NoInline]
func below64(values: [*] u64, index, value: u64)->u64 => cast(u64) (values[index] < value)

#[Swag.NoInline]
func lessSigned32(values: [*] s32, index: u64, value: s32)->u32 => cast(u32) (values[index] < value)

#test
{
    var values64: [4] u64 = [0, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    Swag.assert(equal64(&values64[0], 0, 0) == 1)
    Swag.assert(equal64(&values64[0], 2, 0x8000000000000000) == 1)
    Swag.assert(equal64(&values64[0], 3, 0) == 0)
    Swag.assert(below64(&values64[0], 0, 1) == 1)
    Swag.assert(below64(&values64[0], 2, 0x7FFFFFFFFFFFFFFF) == 0)
    Swag.assert(below64(&values64[0], 3, 0xFFFFFFFFFFFFFFFF) == 0)

    var values32: [4] u32 = [0, 1, 0x80000000, 0xFFFFFFFF]
    Swag.assert(notEqual32(&values32[0], 0, 0) == 0)
    Swag.assert(notEqual32(&values32[0], 1, 0) == 1)
    Swag.assert(notEqual32(&values32[0], 3, 0xFFFFFFFF) == 0)

    var signed32: [4] s32 = [-2147483648's32, -1, 0, 2147483647]
    Swag.assert(lessSigned32(&signed32[0], 0, -1) == 1)
    Swag.assert(lessSigned32(&signed32[0], 1, -1) == 0)
    Swag.assert(lessSigned32(&signed32[0], 3, 0) == 0)
}
