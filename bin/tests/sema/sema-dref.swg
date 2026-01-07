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
    //var v1 = dref v
    //#assert(#typeof(v1) == const AA)
}
