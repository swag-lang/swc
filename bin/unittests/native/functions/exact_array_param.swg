#global private

alias ExactArrayParamNativeHistogram = [8] u16

func accumulateExactHistogram(histogram: ExactArrayParamNativeHistogram, codes: [4] u8)
{
    for code in codes do
        histogram[code] += 1'u16
}

func(T) overwriteExactTail(values: [4] T, value: T)
{
    values[3] = value
}

func patchExactMatrix(grid: [2, 3] s16, base: s16)
{
    grid[0, 1] = base
    grid[1, 0] = base + 1's16
    grid[1, 2] = base + 2's16
}

struct ExactArrayParamNativeMixer {}

impl ExactArrayParamNativeMixer
{
    mtd mix(values: [4] s32, offset: s32)
    {
        values[0] += offset
        values[1] += offset * 2
        values[2] += offset * 3
        values[3] += offset * 4
    }
}

#test
{
    var histogram: ExactArrayParamNativeHistogram = [0, 0, 0, 0, 0, 0, 0, 0]
    accumulateExactHistogram(histogram, [1'u8, 3'u8, 3'u8, 7'u8])
    @assert(histogram[1] == 1'u16)
    @assert(histogram[3] == 2'u16)
    @assert(histogram[7] == 1'u16)
}

#test
{
    var grid: [2, 3] s16 = [[1, 2, 3], [4, 5, 6]]
    patchExactMatrix(grid, 20's16)
    @assert(grid[0, 0] == 1's16)
    @assert(grid[0, 1] == 20's16)
    @assert(grid[1, 0] == 21's16)
    @assert(grid[1, 2] == 22's16)
}

#test
{
    var values: [4] s32 = [2, 4, 6, 8]
    var mixer = ExactArrayParamNativeMixer{}
    mixer.mix(values, 3)
    @assert(values[0] == 5)
    @assert(values[1] == 10)
    @assert(values[2] == 15)
    @assert(values[3] == 20)
}

#test
{
    let patch = func(values: [4] s32)
    {
        values[1] *= 3
        values[2] *= 4
    }

    var values: [4] s32 = [1, 2, 3, 4]
    patch(values)
    @assert(values[0] == 1)
    @assert(values[1] == 6)
    @assert(values[2] == 12)
    @assert(values[3] == 4)
}

#test
{
    var values: [4] u16 = [1'u16, 2'u16, 3'u16, 4'u16]
    overwriteExactTail(values, 99'u16)
    @assert(values[0] == 1'u16)
    @assert(values[3] == 99'u16)
}
