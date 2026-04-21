#global fileprivate

var A: [..] s32
#assert(#typeof(A) == [..] s32)
#assert(#nameof(#typeof(A)) == "[..] s32")

#test
{
    var a: [3] s32 = [1, 2, 3]
    var s: [..] s32 = a
    @assert(s[0] == 1)
    s[1] = 7
    @assert(a[1] == 7)
}

#test
{
    var c: const [..] u8 = "abc"
    @assert(c[0] == 'a')
    @assert(@countof(c) == 3)
}

#test
{
    const s: const [..] s32 = [1, 2, 3]
    @assert(@countof(s) == 3)
    @assert(s[0] == 1)
    @assert(s[2] == 3)
}

#test
{
    var a: [3] s32 = [1, 2, 3]
    var s: const [..] s32 = a
    @assert(@countof(s) == 3)
    @assert(s[1] == 2)
}

#test
{
    var a: [3] s32 = [1, 2, 3]
    var s: [..] s32 = a
    @assert(@countof(s) == 3)
    s[2] = 9
    @assert(a[2] == 9)
}

#test
{
    const s: const [..] u16 = [1'u8, 2'u16, 3]
    @assert(@countof(s) == 3)
    @assert(s[0] == 1'u16)
    @assert(s[2] == 3'u16)
}

#test
{
    var arr: [5] s32 = [10, 20, 30, 40, 50]
    var arrRef: &[5] s32 = &arr
    let arrSlice = arrRef[1 to 3]
    #assert(#typeof(arrSlice) == [..] s32)

    var view: [..] s32 = arr
    let viewRef: const &[..] s32 = &view
    let sub = viewRef[1 until 3]
    #assert(#typeof(sub) == [..] s32)

    let text = "string"
    let textRef: const &string = &text
    let textSlice = textRef[1 to 3]
    #assert(#typeof(textSlice) == string)
}
