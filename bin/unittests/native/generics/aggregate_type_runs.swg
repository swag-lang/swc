#global private

func(T, N: s32) arrayIdentity(values: [N] T)->[N] T => values
func(T) matrixIdentity(values: [2, 4] T)->[2, 4] T  => values

#test
{
    let values = arrayIdentity([
        1_s32, 2_s32, 3_s32, 4_s32, 5_s32, 6_s32, 7_s32, 8_s32,
        9_s32, 10_s32, 11_s32, 12_s32, 13_s32, 14_s32, 15_s32, 16_s32,
        17_s32, 18_s32, 19_s32, 20_s32, 21_s32, 22_s32, 23_s32, 24_s32,
        25_s32, 26_s32, 27_s32, 28_s32, 29_s32, 30_s32, 31_s32, 32_s32])
    #assert(#typeof(values) == [32] s32)
    var total = 0
    for value in values
    {
        total += value
    }
    Swag.require(total == 528)
}

#test
{
    // Later sized values still refine an unsized run, and later runs are revisited.
    let refined = arrayIdentity([1, 2, 3, 4, 5.5_f64, 6.5_f64, 7, 8, 9.5_f64])
    #assert(#typeof(refined) == [9] f64)
    Swag.require(refined[0] == 1.0_f64)
    Swag.require(refined[4] == 5.5_f64)
    Swag.require(refined[7] == 8.0_f64)
    Swag.require(refined[8] == 9.5_f64)

    let alternating = arrayIdentity([1.5_f64, 2_s32, 3.5_f64, 4_s32, 5.5_f64])
    #assert(#typeof(alternating) == [5] f64)
    Swag.require(alternating[1] == 2.0_f64)
    Swag.require(alternating[4] == 5.5_f64)
}

#test
{
    // Equal row types still retain the full traversal of the nested dimension.
    let values = matrixIdentity([[1_u8, 2_u8, 3_u8, 4_u8], [5_u8, 6_u8, 7_u8, 8_u8]])
    #assert(#typeof(values) == [2, 4] u8)
    Swag.require(values[0, 3] == 4_u8)
    Swag.require(values[1, 0] == 5_u8)
    Swag.require(values[1, 3] == 8_u8)
}
