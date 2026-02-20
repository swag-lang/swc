#global internal

#test
{
    struct AA
    {
        x: s32
    }

    var st: AA
    var v: *AA = &st
    var v1 = dref v
    #assert(#typeof(v1) == AA)
}

#test
{
    struct AA
    {
        x: s32
    }

    var st: AA
    var v: const *AA = &st
    var v1 = dref v
    #assert(#typeof(v1) == AA)
}

#test
{
    struct AA
    {
        x: s32
    }

    var st: AA
    var v = &st
    var v1 = dref v
    #assert(#typeof(v) == *AA)
    #assert(#typeof(v1) == AA)
}

#test
{
    struct AA
    {
        x: s32
    }

    var st: AA
    var v: *AA = &st
    var pp = &v
    var v1 = dref pp
    #assert(#typeof(pp) == **AA)
    #assert(#typeof(v1) == *AA)
}

#test
{
    struct AA
    {
        x: s32
    }

    var st: AA
    var v1 = dref &st
    #assert(#typeof(v1) == AA)
}
