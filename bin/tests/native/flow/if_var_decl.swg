#global fileprivate // 

#test
{
    var result = 0
    if var x = 1
    {
        var y = x
        result = y
    }
    else
    {
        var z = x
        result = z
    }
    @assert(result == 1)
}

#test
{
    var result = 0
    if var x: s32 = 1 where x
    {
        var y = x
        result = y
    }
    @assert(result == 1)
}

#test
{
    var result = 0
    if var x = 0
    {
        result = -1
    }
    else
    {
        result = x + 2
    }
    @assert(result == 2)
}

#test
{
    var result = 0
    if var x = 0 where x == 0
    {
        result = x + 3
    }
    else
    {
        result = -1
    }
    @assert(result == 3)
}

#test
{
    var result = 0
    if var x = 1 where false
    {
        result = -1
    }
    else
    {
        result = x + 1
    }
    @assert(result == 2)
}

#test
{
    var result = 0
    var base = 42
    if var x: #null *s32 = &base where x != null
    {
        result = 1
    }
    else
    {
        result = -1
    }
    @assert(result == 1)
}

#test
{
    var result = 0
    if var x: #null string = null where x == null
    {
        result = 1
    }
    else
    {
        result = -1
    }
    @assert(result == 1)
}

#test
{
    var result = 0
    if var x: #null [..] s32 = null where x == null
    {
        result = 1
    }
    else
    {
        result = -1
    }
    @assert(result == 1)
}
