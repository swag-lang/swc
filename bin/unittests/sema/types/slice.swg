#global private

var A: #null [..] s32
#assert(#typeof(A) == #null [..] s32)
#assert(#nameof(#typeof(A)) == "#null [..] s32")

func semaTest001()
{
    var a: [3] s32 = [1, 2, 3]
    var s: [..] s32 = a
    @assert(s[0] == 1)
    s[1] = 7
    @assert(a[1] == 7)
}

func semaTest002()
{
    var c: const [..] u8 = "abc"
    @assert(c[0] == 'a')
    @assert(@countof(c) == 3)
}

func semaTest003()
{
    const s: const [..] s32 = [1, 2, 3]
    @assert(@countof(s) == 3)
    @assert(s[0] == 1)
    @assert(s[2] == 3)
}

func semaTest004()
{
    var a: [3] s32 = [1, 2, 3]
    var s: const [..] s32 = a
    @assert(@countof(s) == 3)
    @assert(s[1] == 2)
}

func semaTest005()
{
    var a: [3] s32 = [1, 2, 3]
    var s: [..] s32 = a
    @assert(@countof(s) == 3)
    s[2] = 9
    @assert(a[2] == 9)
}

func semaTest006()
{
    const s: const [..] u16 = [1'u8, 2'u16, 3]
    @assert(@countof(s) == 3)
    @assert(s[0] == 1'u16)
    @assert(s[2] == 3'u16)
}

func semaTest007()
{
    var arr:    [5] s32 = [10, 20, 30, 40, 50]
    var arrRef: &[5] s32 = &arr
    let arrSlice = arrRef[1 to 3]
    #assert(#nameof(#typeof(arrSlice)) == "[..] s32")

    var view:    [..] s32 = arr
    let viewRef: const &[..] s32 = &view
    let sub = viewRef[1 until 3]
    #assert(#typeof(sub) == [..] s32)

    let text = "string"
    let textRef: const &string = &text
    let textSlice = textRef[1 to 3]
    #assert(#typeof(textSlice) == string)
}
