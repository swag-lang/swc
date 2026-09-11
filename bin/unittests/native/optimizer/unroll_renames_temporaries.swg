#global private
using Swag

// A counted loop the unroller lays out flat: the temporaries of each copy,
// the accumulators that continue across copies, and the last value read
// after the loop must all keep their meaning.

#[Swag.Optimize(true)]
func scaleRows(dst: [*] u8, src: const [*] u8, stride: u64)->u32
{
    var sum  = 0'u32
    var last = 0'u8
    for row in 4'u64
    {
        let value = src[row * stride]
        let twice = cast(u8) (value * 2)
        dst[row * stride]     = twice
        dst[row * stride + 1] = twice
        sum += cast(u32) twice
        last = twice
    }

    return sum + cast(u32) last
}

#[Swag.Optimize(true)]
func fillRows(dst: [*] u8, stride: u64, values: const [*] u8)
{
    for row in 8'u64
    {
        for column in 8'u64 do
            dst[row * stride + column] = values[row]
    }
}

#[Swag.Optimize(true)]
func chain(values: const [*] s32)->s32
{
    var previous = values[0]
    var result   = 0's32
    for i in 1'u64 until 5
    {
        let current = values[i]
        result += current - previous
        previous = current
    }

    return result + previous
}

#test
{
    var src: [4 * 16] u8
    var dst: [4 * 16] u8
    for i in 4 do
        src[i * 16] = cast(u8) (i + 1)

    let total = scaleRows(&dst[0], &src[0], 16)
    Swag.assert(dst[0] == 2 and dst[1] == 2 and dst[16] == 4 and dst[17] == 4 and dst[48] == 8)
    Swag.assert(total == 2 + 4 + 6 + 8 + 8)

    var values: [8] u8 = [10, 11, 12, 13, 14, 15, 16, 17]
    var out:    [8 * 16] u8
    fillRows(&out[0], 16, &values[0])
    Swag.assert(out[0] == 10 and out[7] == 10 and out[8] == 0 and out[16] == 11 and out[7 * 16 + 7] == 17)

    var steps: [5] s32 = [3, 5, 8, 13, 21]
    Swag.assert(chain(&steps[0]) == (21 - 3) + 21)
}
