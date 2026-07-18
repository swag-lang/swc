#global #[Swag.ExplicitNullability]
#test
{
    var grid: [2, 3] s32 = [[11, 12, 13], [21, 22, 23]]
    let rows = cast(#nonull [..] [3] s32) grid

    #assert(#typeof(rows[1, 2]) == s32)
    @assert(rows[1, 2] == rows[1][2])
    @assert(rows[0, 1] + rows[1, 0] == 33)
}
