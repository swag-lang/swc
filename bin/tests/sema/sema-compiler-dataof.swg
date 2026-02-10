#global internal

#test
{
    var a: [..] s32
    var b = @dataof(a)
    #assert(#typeof(b) == [*] s32)

    var c: string
    var d = @dataof(c)
    #assert(#typeof(d) == const [*] u8)

    var e: cstring
    var f = @dataof(e)
    #assert(#typeof(f) == const [*] u8)

    var g: [5] s32
    var h = @dataof(g)
    #assert(#typeof(h) == [*] s32)

    var i: any
    var j = @dataof(i)
    #assert(#typeof(j) == [*] void)
}

#test
{
    var s: string = "abc"
    var p = @dataof(s)
    @assert(p[0] == 'a')
    @assert(p[1] == 'b')
    @assert(p[2] == 'c')
}

#test
{
    var arr: [3] u8 = [1, 2, 3]
    var p = @dataof(arr)
    @assert(p[0] == 1'u8)
    @assert(p[1] == 2'u8)
    @assert(p[2] == 3'u8)
}

#test
{
    var s: string = null
    var p = @dataof(s)
    #assert(#typeof(p) == const [*] u8)
}

#test
{
    var arr: [2] s32 = [1, 2]
    var p = @dataof(arr)
    p[0] = 7
    @assert(arr[0] == 7)
}
