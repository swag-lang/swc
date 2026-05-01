#global fileprivate // 

#[Swag.Strict]
alias StrictS32Triple = [3] s32

const StrictTripleGlobal: StrictS32Triple = cast(StrictS32Triple) [4, 5, 6]

func strictAliasGlobalSum()->s32
{
    return StrictTripleGlobal[0] + StrictTripleGlobal[1] + StrictTripleGlobal[2]
}

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

func cstringToConstByteView()->bool
{
    var data: [5] u8 = ['v''u8, 'i''u8, 'e''u8, 'w''u8, 0]
    var text: cstring = cast(cstring) &data[0]
    let bytes = cast(const [..] u8) text
    #assert(#typeof(bytes) == const [..] u8)
    return @countof(bytes) == 4 and bytes[0] == 'v''u8 and bytes[3] == 'w''u8
}

func constCStringToByteView()->bool
{
    var text: const cstring = cast(const cstring) @dataof("view")
    let bytes = cast(const [..] u8) text
    #assert(#typeof(bytes) == const [..] u8)
    return @countof(bytes) == 4 and bytes[0] == 'v''u8 and bytes[3] == 'w''u8
}

func cstringToStringView()->bool
{
    var text: const cstring = cast(const cstring) @dataof("text")
    let view = cast(string) text
    return @countof(view) == 4 and view == "text"
}

func constCStringExprToByteView()->bool
{
    let bytes = cast(const [..] u8) (cast(const cstring) @dataof("expr"))
    #assert(#typeof(bytes) == const [..] u8)
    return @countof(bytes) == 4 and bytes[0] == 'e''u8 and bytes[3] == 'r''u8
}

func constCStringExprToStringView()->bool
{
    let view = cast(string) (cast(const cstring) @dataof("expr"))
    return @countof(view) == 4 and view == "expr"
}

#test
{
    let text = makeConstArrayString()
    @assert(strictAliasGlobalSum() == 15)
    @assert(localArrayToSliceView())
    @assert(@countof(text) == 3)
    @assert(text == "xyz")
    @assert(stringToConstBytes())
    @assert(sliceToStringRoundtrip())
    @assert(wordArrayToByteView())
    @assert(cstringToConstByteView())
    @assert(constCStringToByteView())
    @assert(cstringToStringView())
    @assert(constCStringExprToByteView())
    @assert(constCStringExprToStringView())
}
