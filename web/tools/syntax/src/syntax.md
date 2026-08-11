```swag
#[Swag.Inline]
func(T) clamp(value, low, high: T)->T => value < low ? low : value > high ? high : value

// Mirrors a struct, turning every field into a 'bool' at compile time.
struct(T) IsSet
{
    #ast
    {
        var code = StrConv.StringBuilder{}
        for field in #typeof(T).fields do
            code.appendFormat("%: bool\n", field.name)
        return code.toString()
    }
}

#test
{
    const Powers: [4] s32 = #run
    {
        var table: [4] s32
        for i in @countof(table) do
            table[i] = 1 << cast(u32) i
        return table
    }

    #assert Powers[3] == 8
    Debug.assert(clamp(12, 0, 10) == 10)
}
