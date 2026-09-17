#global private

#[Swag.NoInline]
func pairEqual64(values: [*] u64, index: u64)->u64 => cast(u64) (values[index] == values[index + 1])

#[Swag.NoInline]
func arraysEqual64(left, right: [*] u64, index: u64)->u64 => cast(u64) (left[index] == right[index])

#[Swag.NoInline]
func pairBelow32(values: [*] u32, index: u64)->u32 => cast(u32) (values[index] < values[index + 1])

#test
{
    var first:  [4] u64 = [0, 0, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    var second: [4] u64 = [0, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFE]
    Swag.assert(pairEqual64(&first[0], 0) == 1)
    Swag.assert(pairEqual64(&first[0], 1) == 0)
    Swag.assert(pairEqual64(&first[0], 2) == 0)
    Swag.assert(arraysEqual64(&first[0], &second[0], 0) == 1)
    Swag.assert(arraysEqual64(&first[0], &second[0], 1) == 0)
    Swag.assert(arraysEqual64(&first[0], &second[0], 2) == 1)

    var narrow: [4] u32 = [0, 1, 0xFFFFFFFF, 0]
    Swag.assert(pairBelow32(&narrow[0], 0) == 1)
    Swag.assert(pairBelow32(&narrow[0], 1) == 1)
    Swag.assert(pairBelow32(&narrow[0], 2) == 0)
}
