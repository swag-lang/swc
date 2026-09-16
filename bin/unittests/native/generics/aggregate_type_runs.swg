#global private

func(T, N: s32) arrayIdentity(values: [N] T)->[N] T => values
func(T) matrixIdentity(values: [2, 4] T)->[2, 4] T  => values

#test
{
    let values = arrayIdentity([
        1's32, 2's32, 3's32, 4's32, 5's32, 6's32, 7's32, 8's32,
        9's32, 10's32, 11's32, 12's32, 13's32, 14's32, 15's32, 16's32,
        17's32, 18's32, 19's32, 20's32, 21's32, 22's32, 23's32, 24's32,
        25's32, 26's32, 27's32, 28's32, 29's32, 30's32, 31's32, 32's32])
    #assert(#typeof(values) == [32] s32)
    var total = 0
    for value in values do
        total += value
    Swag.assert(total == 528)
}

#test
{
    // Later sized values still refine an unsized run, and later runs are revisited.
    let refined = arrayIdentity([1, 2, 3, 4, 5.5'f64, 6.5'f64, 7, 8, 9.5'f64])
    #assert(#typeof(refined) == [9] f64)
    Swag.assert(refined[0] == 1.0'f64)
    Swag.assert(refined[4] == 5.5'f64)
    Swag.assert(refined[7] == 8.0'f64)
    Swag.assert(refined[8] == 9.5'f64)

    let alternating = arrayIdentity([1.5'f64, 2's32, 3.5'f64, 4's32, 5.5'f64])
    #assert(#typeof(alternating) == [5] f64)
    Swag.assert(alternating[1] == 2.0'f64)
    Swag.assert(alternating[4] == 5.5'f64)
}

#test
{
    // Equal row types still retain the full traversal of the nested dimension.
    let values = matrixIdentity([[1'u8, 2'u8, 3'u8, 4'u8], [5'u8, 6'u8, 7'u8, 8'u8]])
    #assert(#typeof(values) == [2, 4] u8)
    Swag.assert(values[0, 3] == 4'u8)
    Swag.assert(values[1, 0] == 5'u8)
    Swag.assert(values[1, 3] == 8'u8)
}
