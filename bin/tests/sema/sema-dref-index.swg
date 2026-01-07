#global internal

#test
{
    var buf: [4] s32
    var a = buf[0]
    #assert(#typeof(a) == s32)

    var ptr = &buf[0]
    #assert(#typeof(ptr) == *s32)
}