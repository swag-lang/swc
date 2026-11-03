#global private

var A: [..] s32?
#assert(#typeof(A) == [..] s32?)
#assert(#nameof(#typeof(A)) == "[..] s32?")

#test
{
    var a: [3] s32  = [1, 2, 3]
    var s: [..] s32 = a
    Swag.require(s[0] == 1)
    s[1] = 7
    Swag.require(a[1] == 7)
}

#test
{
    var c: const [..] u8 = "abc"
    Swag.require(c[0] == 'a')
    Swag.require(c.count == 3)
}

#test
{
    const s: const [..] s32 = [1, 2, 3]
    Swag.require(s.count == 3)
    Swag.require(s[0] == 1)
    Swag.require(s[2] == 3)
}

#test
{
    var a: [3] s32        = [1, 2, 3]
    var s: const [..] s32 = a
    Swag.require(s.count == 3)
    Swag.require(s[1] == 2)
}

#test
{
    var a: [3] s32  = [1, 2, 3]
    var s: [..] s32 = a
    Swag.require(s.count == 3)
    s[2] = 9
    Swag.require(a[2] == 9)
}

#test
{
    const s: const [..] u16 = [1'u8, 2'u16, 3]
    Swag.require(s.count == 3)
    Swag.require(s[0] == 1'u16)
    Swag.require(s[2] == 3'u16)
}

#test
{
    var arr: [5] s32 = [10, 20, 30, 40, 50]
    let slice        = arr[1 to 3]

    Swag.require(slice.count == 3)
    Swag.require(slice[0] == 20)
    Swag.require(slice[2] == 40)

    slice[1] = 77
    Swag.require(arr[2] == 77)
}

#test
{
    var arr: [5] s32 = [10, 20, 30, 40, 50]
    let slice        = arr[until 2]
    let full         = arr[to]

    Swag.require(slice.count == 2)
    Swag.require(slice[0] == 10)
    Swag.require(slice[1] == 20)
    Swag.require(full.count == 5)
    Swag.require(full[4] == 50)
}

#test
{
    var arr: [5] s32 = [10, 20, 30, 40, 50]
    let slice0       = arr[1 to 4]
    let slice1       = slice0[1 until 3]

    Swag.require(slice0.count == 4)
    Swag.require(slice1.count == 2)
    Swag.require(slice1[0] == 30)
    Swag.require(slice1[1] == 40)

    slice1[0] = 88
    Swag.require(arr[2] == 88)
}

#test
{
    let str = "string"
    let a   = str[1 to 3]
    let b   = str[2 to]
    let c   = str[until 2]

    Swag.require(a == "tri")
    Swag.require(b == "ring")
    Swag.require(c == "st")
}

#test
{
    let cstr: const cstring = cast(const cstring, ("slice").buffer)
    let a    = cstr[1 to 3]
    let b    = cstr[2 to]
    let c    = cstr[until 2]
    let full = cstr[to]

    Swag.require(a == "lic")
    Swag.require(b == "ice")
    Swag.require(c == "sl")
    Swag.require(full == "slice")
}

#test
{
    var arr:    [5] s32  = [10, 20, 30, 40, 50]
    var arrRef: *[5] s32 = &arr
    let arrSlice         = arrRef[][1 to 3]
    Swag.require(arrSlice.count == 3)
    Swag.require(arrSlice[0] == 20)
    arrSlice[1] = 77
    Swag.require(arr[2] == 77)

    var view:    [..] s32        = arr
    let viewRef: const *[..] s32 = &view
    let sub = viewRef[][1 until 3]
    Swag.require(sub.count == 2)
    Swag.require(sub[0] == 20)
    Swag.require(sub[1] == 77)

    let text = "string"
    let textRef: const *string = &text
    Swag.require(textRef[][1 to 3] == "tri")
}
