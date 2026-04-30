#global fileprivate

#[Swag.Strict]
alias StrictS32Triple = [3] s32

func makeConstArrayString()->string
{
    const data: [3] u8 = [120, 121, 122]
    return cast(string) data
}

#test
{
    func arrayLiteralToStrictAlias()->s32
    {
        var values: StrictS32Triple = cast(StrictS32Triple) [4, 5, 6]
        return values[0] + values[1] + values[2]
    }

    const V = #run arrayLiteralToStrictAlias()
    #assert(V == 15)
}

#test
{
    func localArrayToSliceView()->bool
    {
        var data: [4] s32 = [1, 2, 3, 4]
        let values = cast([..] s32) data
        return @countof(values) == 4 and values[0] == 1 and values[1] == 2 and values[3] == 4
    }

    const V = #run localArrayToSliceView()
    #assert(V)
}

#test
{
    const text = #run makeConstArrayString()

    #assert(@countof(text) == 3)
    #assert(text == "xyz")
}

#test
{
    func stringToConstBytes()->bool
    {
        let text: string = "ABCD"
        let bytes = cast(const [..] u8) text
        return @countof(bytes) == 4 and bytes[0] == 65'u8 and bytes[3] == 68'u8
    }

    const V = #run stringToConstBytes()
    #assert(V)
}

#test
{
    func sliceToStringRoundtrip()->bool
    {
        var data: [5] u8 = [72, 101, 108, 108, 111]
        let bytes = cast([..] u8) data
        let text = cast(string) bytes
        let back = cast(const [..] u8) text
        return text == "Hello" and @countof(back) == 5 and back[1] == 101'u8 and back[4] == 111'u8
    }

    const V = #run sliceToStringRoundtrip()
    #assert(V)
}

#test
{
    func wordArrayToByteView()->bool
    {
        var words: [2] u16 = [0x0102'u16, 0x0304'u16]
        let bytes = cast([..] u8) words
        var sum: u32 = 0
        foreach value in bytes do
            sum += cast(u32) value
        return @countof(bytes) == 4 and sum == 10'u32
    }

    const V = #run wordArrayToByteView()
    #assert(V)
}
