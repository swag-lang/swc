#global fileprivate // 

func makeConstArrayString()->string
{
    const data: [3] u8 = [120, 121, 122]
    return cast(string) data
}

func localArrayToSliceView()->bool
{
    var data: [4] s32 = [1, 2, 3, 4]
    let values = cast([..] s32) data
    return @countof(values) == 4 and values[0] == 1 and values[1] == 2 and values[3] == 4
}

func stringToConstBytes()->bool
{
    let text: string = "ABCD"
    let bytes = cast(const [..] u8) text
    return @countof(bytes) == 4 and bytes[0] == 65'u8 and bytes[3] == 68'u8
}

func sliceToStringRoundtrip()->bool
{
    var data: [5] u8 = [72, 101, 108, 108, 111]
    let bytes = cast([..] u8) data
    let text = cast(string) bytes
    let back = cast(const [..] u8) text
    return text == "Hello" and @countof(back) == 5 and back[1] == 101'u8 and back[4] == 111'u8
}

func wordArrayToByteView()->bool
{
    var words: [2] u16 = [0x0102'u16, 0x0304'u16]
    let bytes = cast([..] u8) words
    var sum: u32 = 0
    foreach value in bytes do
        sum += cast(u32) value
    return @countof(bytes) == 4 and sum == 10'u32
}

#test
{
    let text = makeConstArrayString()
    @assert(localArrayToSliceView())
    @assert(@countof(text) == 3)
    @assert(text == "xyz")
    @assert(stringToConstBytes())
    @assert(sliceToStringRoundtrip())
    @assert(wordArrayToByteView())
}
