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