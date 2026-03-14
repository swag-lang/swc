#global fileprivate // swc-option suite-test

#test
{
    var x: *s32 = null
    var y: const *s32 = null

    var y0 = cast(const *s32) x
    #assert(#typeof(y0) == const *s32)
    var x1 = cast #unconst (*s32) y0
    #assert(#typeof(x1) == *s32)
}

#test
{
    var x: *s32 = null
    var b: [*]s32 = null

    var v: *s32 = b
    #assert(#typeof(v) == *s32)

    var v2 = cast(*s32) b
    #assert(#typeof(v2) == *s32)

}

#test
{
    var x: *s32 = null
    var b: [*]s32 = null

    var v: *s32 = b
    #assert(#typeof(v) == *s32)

    var v2 = cast(*s32) b
    #assert(#typeof(v2) == *s32)

    var b3 = cast([*]s32) x
    #assert(#typeof(b3) == [*]s32)
}

#test
{
    var x: *s32 = null
    var y = cast(*u8) x
    #assert(#typeof(y) == *u8)
}



#test
{
    var x: const *s32 = null
    var y = cast #unconst (*u8) x
    #assert(#typeof(y) == *u8)
}

#test
{
    var x: [*]s32 = null
    var y = cast([*]u8) x
    #assert(#typeof(y) == [*]u8)
}

#test
{
    var x: *s32 = null
    var y = cast([*]u8) x
    #assert(#typeof(y) == [*]u8)

    var x1: u64
    var v1 = cast(*void) x1

    var x2: u32
}






#test
{
    var x: const *s32 = null
    var y = cast(const *u8) x
    #assert(#typeof(y) == const *u8)
}

#test
{
    var x: const [*]s32 = null
    var y = cast(const [*]u8) x
    #assert(#typeof(y) == const [*]u8)
}


