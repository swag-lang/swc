#global fileprivate

var B: s32
var C: f32 = 1
#assert(#typeof(C) == f32)
var D = 1.0
#assert(#typeof(D) == f32)

#test
{
    let a = 2
    var b = 2
    #assert(#typeof(a) == s32)
    #assert(#typeof(b) == s32)
}

#test
{
    var x = true
    #assert(#typeof(x) == bool)

    var y: u16 = 5
    var z = y
    #assert(#typeof(z) == u16)
}

#test
{
    let a = 5
    const b = a + 7
    #assert(b == 12)
}

#test
{
    let a = 1
    var p = &a
    #assert(#typeof(p) == const *s32)
}
