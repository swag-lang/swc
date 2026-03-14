#global fileprivate // swc-option suite-test

#test
{
    var arr: [3] s32 = [1, 2, 3]
    foreach v in arr
    {
        #assert(#typeof(v) == s32)
        var x = v
    }
}

#test
{
    var arr: [2] s32 = [1, 2]
    foreach v, i in arr
    {
        #assert(#typeof(v) == s32)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
    }

}

#test
{
    var arr: [2] s32 = [1, 2]
    foreach v in arr where v > 0
    {
        var x = v
    }
}


#test
{
    var arr: [2] u32 = [10'u32, 20]
    foreach &v in arr
    {
        var x = dref v
    }
}

#test
{
    var text: string = "AB"
    foreach v, i in text
    {
        #assert(#typeof(v) == u8)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
    }
}

#test
{
    var arr: [2] s32 = [3, 4]
    var sl = cast([..] s32) arr
    foreach v, i in sl
    {
        #assert(#typeof(v) == s32)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
    }
}



#test
{
    func foreachVariadicAny(values: ...)
    {
        foreach v, i in values
        {
            #assert(#typeof(v) == any)
            #assert(#typeof(i) == u64)
            var x = v
            var y = i
        }
    }
}

#test
{
    func foreachVariadicTyped(values: s32...)
    {
        foreach v, i in values
        {
            #assert(#typeof(v) == s32)
            #assert(#typeof(i) == u64)
            var x = v
            var y = i
        }
    }
}

#test
{
    func foreachVariadicAnyErr(values: ...)
    {
        foreach v in values
        {
        }
    }
}

#test
{
    func foreachVariadicTypedErr(values: s32...)
    {
        foreach v, i in values
        {
        }
    }
}
