#global private

alias ExactArrayParamNativeHistogram = [8] u16

func accumulateExactHistogram(histogram: ExactArrayParamNativeHistogram, codes: [4] u8)
{
    for code in codes
    {
        histogram[code] += 1_u16
    }
}

func(T) overwriteExactTail(values: [4] T, value: T)
{
    values[3] = value
}

func patchExactMatrix(grid: [2, 3] s16, base: s16)
{
    grid[0, 1] = base
    grid[1, 0] = base + 1_s16
    grid[1, 2] = base + 2_s16
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
    accumulateExactHistogram(histogram, [1_u8, 3_u8, 3_u8, 7_u8])
    Swag.require(histogram[1] == 1_u16)
    Swag.require(histogram[3] == 2_u16)
    Swag.require(histogram[7] == 1_u16)
}

#test
{
    var grid: [2, 3] s16 = [[1, 2, 3], [4, 5, 6]]
    patchExactMatrix(grid, 20_s16)
    Swag.require(grid[0, 0] == 1_s16)
    Swag.require(grid[0, 1] == 20_s16)
    Swag.require(grid[1, 0] == 21_s16)
    Swag.require(grid[1, 2] == 22_s16)
}

#test
{
    var values: [4] s32 = [2, 4, 6, 8]
    var mixer = ExactArrayParamNativeMixer{}
    mixer.mix(values, 3)
    Swag.require(values[0] == 5)
    Swag.require(values[1] == 10)
    Swag.require(values[2] == 15)
    Swag.require(values[3] == 20)
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
    Swag.require(values[0] == 1)
    Swag.require(values[1] == 6)
    Swag.require(values[2] == 12)
    Swag.require(values[3] == 4)
}

#test
{
    var values: [4] u16 = [1_u16, 2_u16, 3_u16, 4_u16]
    overwriteExactTail(values, 99_u16)
    Swag.require(values[0] == 1_u16)
    Swag.require(values[3] == 99_u16)
}
