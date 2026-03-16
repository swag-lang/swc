#global fileprivate // swc-option suite-test

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
    let slice = arr[1 to 3]

    @assert(@countof(slice) == 3)
    @assert(slice[0] == 20)
    @assert(slice[2] == 40)

    slice[1] = 77
    @assert(arr[2] == 77)
}

#test
{
    var arr: [5] s32 = [10, 20, 30, 40, 50]
    let slice = arr[ until 2]
    let full  = arr[ to ]

    @assert(@countof(slice) == 2)
    @assert(slice[0] == 10)
    @assert(slice[1] == 20)
    @assert(@countof(full) == 5)
    @assert(full[4] == 50)
}

#test
{
    var arr: [5] s32 = [10, 20, 30, 40, 50]
    let slice0 = arr[1 to 4]
    let slice1 = slice0[1 until 3]

    @assert(@countof(slice0) == 4)
    @assert(@countof(slice1) == 2)
    @assert(slice1[0] == 30)
    @assert(slice1[1] == 40)

    slice1[0] = 88
    @assert(arr[2] == 88)
}

#test
{
    let str = "string"
    let a = str[1 to 3]
    let b = str[2 to ]
    let c = str[ until 2]

    @assert(a == "tri")
    @assert(b == "ring")
    @assert(c == "st")
}
