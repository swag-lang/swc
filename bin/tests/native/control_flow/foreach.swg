#global fileprivate // swc-option suite-test

#test
{
    var arr: [3] s32 = [1, 2, 3]
    var sum = 0
    foreach v in arr
    {
        #assert(#typeof(v) == s32)
        var x = v
        sum += x
    }
    @assert(sum == 6)
}

#test
{
    var arr: [2] s32 = [1, 2]
    var sumV = 0
    var sumI = 0
    foreach v, i in arr
    {
        #assert(#typeof(v) == s32)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
        sumV += x
        sumI += cast(s32) y
    }
    @assert(sumV == 3)
    @assert(sumI == 1)
}

#test
{
    var arr: [2] s32 = [1, 2]
    var sum = 0
    foreach v in arr where v > 0
    {
        var x = v
        sum += x
    }
    @assert(sum == 3)
}


#test
{
    var arr: [2] u32 = [10'u32, 20]
    foreach &v in arr
    {
        dref v += 1
    }
    @assert(arr[0] == 11)
    @assert(arr[1] == 21)
}

#test
{
    var text: string = "AB"
    var sumV = 0
    var sumI = 0
    foreach v, i in text
    {
        #assert(#typeof(v) == u8)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
        sumV += cast(s32) x
        sumI += cast(s32) y
    }
    @assert(sumV == cast(s32) 'A''u8 + cast(s32) 'B''u8)
    @assert(sumI == 1)
}

#test
{
    var arr: [2] s32 = [3, 4]
    var sl = cast([..] s32) arr
    var sumV = 0
    var sumI = 0
    foreach v, i in sl
    {
        #assert(#typeof(v) == s32)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
        sumV += x
        sumI += cast(s32) y
    }
    @assert(sumV == 7)
    @assert(sumI == 1)
}



#test
{
    func foreachVariadicAny(values: ...)->u64
    {
        var count: u64
        foreach v, i in values
        {
            #assert(#typeof(v) == any)
            #assert(#typeof(i) == u64)
            var x = v
            var y = i
            count += 1
        }
        return count
    }
    @assert(foreachVariadicAny(1, 2, 3) == 3)
}

#test
{
    func foreachVariadicTyped(values: s32...)->u64
    {
        var count: u64
        foreach v, i in values
        {
            #assert(#typeof(v) == s32)
            #assert(#typeof(i) == u64)
            var x = v
            var y = i
            count += 1
        }
        return count
    }
    @assert(foreachVariadicTyped(1, 2, 3) == 3)
}

#test
{
    func foreachVariadicAnyErr(values: ...)->u64
    {
        var count: u64
        foreach v in values
        {
            count += 1
        }
        return count
    }
    @assert(foreachVariadicAnyErr(1, true, "a") == 3)
}

#test
{
    func foreachVariadicTypedErr(values: s32...)->u64
    {
        var count: u64
        foreach v, i in values
        {
            count += 1
        }
        return count
    }
    @assert(foreachVariadicTypedErr(5, 6) == 2)
}
