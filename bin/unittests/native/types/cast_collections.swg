#global private

#[Swag.Strict]
alias StrictS32Triple = [3] s32

const StrictTripleGlobal: StrictS32Triple = cast(StrictS32Triple, [4, 5, 6])

func strictAliasGlobalSum()->s32
{
    return StrictTripleGlobal[0] + StrictTripleGlobal[1] + StrictTripleGlobal[2]
}

func makeConstArrayString()->string
{
    const data: [3] u8 = [120, 121, 122]
    return cast(string, data)
}

func localArrayToSliceView()->bool
{
    var data: [4] s32 = [1, 2, 3, 4]
    let values        = cast([..] s32, data)
    return values.count == 4 and values[0] == 1 and values[1] == 2 and values[3] == 4
}

func stringToConstBytes()->bool
{
    let text: string = "ABCD"
    let bytes        = cast(const [..] u8, text)
    return bytes.count == 4 and bytes[0] == 65_u8 and bytes[3] == 68_u8
}

func sliceToStringRoundtrip()->bool
{
    var data: [5] u8 = [72, 101, 108, 108, 111]
    let bytes        = cast([..] u8, data)
    let text         = cast(string, bytes)
    let back         = cast(const [..] u8, text)
    return text == "Hello" and back.count == 5 and back[1] == 101_u8 and back[4] == 111_u8
}

func wordArrayToByteView()->bool
{
    var words: [2] u16 = [0x0102_u16, 0x0304_u16]
    let bytes          = cast([..] u8, words)
    var sum:   u32     = 0
    for value in bytes
    {
        sum += cast(u32, value)
    }
    return bytes.count == 4 and sum == 10_u32
}

func constArrayToConstSliceView()->bool
{
    const data: [3] u8 = [7, 8, 9]
    let bytes = cast(const [..] u8, data)
    #assert(#typeof(bytes) == const [..] u8)
    return bytes.count == 3 and bytes[0] == 7_u8 and bytes[2] == 9_u8
}

func cstringToConstByteView()->bool
{
    var data: [5] u8  = ['v'_u8, 'i'_u8, 'e'_u8, 'w'_u8, 0]
    var text: cstring = cast(cstring, &data[0])
    let bytes         = cast(const [..] u8, text)
    #assert(#typeof(bytes) == const [..] u8)
    return bytes.count == 4 and bytes[0] == 'v'_u8 and bytes[3] == 'w'_u8
}

func constCStringToByteView()->bool
{
    var text: const cstring = cast(const cstring, ("view").buffer)
    let bytes = cast(const [..] u8, text)
    #assert(#typeof(bytes) == const [..] u8)
    return bytes.count == 4 and bytes[0] == 'v'_u8 and bytes[3] == 'w'_u8
}

func cstringToStringView()->bool
{
    var text: const cstring = cast(const cstring, ("text").buffer)
    let view = cast(string, text)
    return view.count == 4 and view == "text"
}

func constArrayToConstCStringView()->bool
{
    const data: [4] u8 = ['v'_u8, 'i'_u8, 'e'_u8, 0]
    let text = cast(const cstring, data)
    #assert(#typeof(text) == const cstring)
    return text.count == 3 and text[0] == 'v'_u8 and text[2] == 'e'_u8
}

func constPointerToConstCStringView()->bool
{
    var data: [4] u8       = ['p'_u8, 't'_u8, 'r'_u8, 0]
    let ptr:  const [*] u8 = cast(const [*] u8, &data[0])
    let text               = cast(const cstring, ptr)
    #assert(#typeof(text) == const cstring)
    return text.count == 3 and text[0] == 'p'_u8 and text[2] == 'r'_u8
}

func constCStringExprToByteView()->bool
{
    let bytes = cast(const [..] u8, cast(const cstring, ("expr").buffer))
    #assert(#typeof(bytes) == const [..] u8)
    return bytes.count == 4 and bytes[0] == 'e'_u8 and bytes[3] == 'r'_u8
}

func constCStringExprToStringView()->bool
{
    let view = cast(string, cast(const cstring, ("expr").buffer))
    return view.count == 4 and view == "expr"
}

#test
{
    let text = makeConstArrayString()
    Swag.require(strictAliasGlobalSum() == 15)
    Swag.require(localArrayToSliceView())
    Swag.require(text.count == 3)
    Swag.require(text == "xyz")
    Swag.require(stringToConstBytes())
    Swag.require(sliceToStringRoundtrip())
    Swag.require(wordArrayToByteView())
    Swag.require(constArrayToConstSliceView())
    Swag.require(cstringToConstByteView())
    Swag.require(constCStringToByteView())
    Swag.require(cstringToStringView())
    Swag.require(constArrayToConstCStringView())
    Swag.require(constPointerToConstCStringView())
    Swag.require(constCStringExprToByteView())
    Swag.require(constCStringExprToStringView())
}
