#global fileprivate

#test
{
    func ifDeclSimple()->s32
    {
        var result = 0
        if var x = 1
        {
            result = x
        }
        else
        {
            result = -1
        }
        return result
    }

    const V = #run ifDeclSimple()
    @assert(V == 1)
}

#test
{
    func ifDeclWithTypeWhere()->s32
    {
        var result = 0
        if var x: s32 = 1 where x
        {
            result = x + 1
        }
        return result
    }

    const V = #run ifDeclWithTypeWhere()
    @assert(V == 2)
}

#test
{
    func ifDeclFalseElse()->s32
    {
        if var x = 0
        {
            return -1
        }
        else
        {
            return x + 2
        }
    }

    const V = #run ifDeclFalseElse()
    @assert(V == 2)
}

#test
{
    func ifDeclWhereZeroIsTrue()->s32
    {
        if var x = 0 where x == 0
        {
            return x + 3
        }
        else
        {
            return -1
        }
    }

    const V = #run ifDeclWhereZeroIsTrue()
    @assert(V == 3)
}

#test
{
    func ifDeclWhereFalseUsesElse()->s32
    {
        if var x = 1 where false
        {
            return -1
        }
        else
        {
            return x + 1
        }
    }

    const V = #run ifDeclWhereFalseUsesElse()
    @assert(V == 2)
}

#test
{
    func ifDeclNullablePointer()->s32
    {
        var base = 42
        if var x: #null *s32 = &base where x != null
        {
            return 1
        }

        return -1
    }

    const V = #run ifDeclNullablePointer()
    @assert(V == 1)
}

#test
{
    func ifDeclNullableStringNull()->s32
    {
        if var x: #null string = null where x == null
        {
            return 1
        }
        return -1
    }

    const V = #run ifDeclNullableStringNull()
    @assert(V == 1)
}

#test
{
    func ifDeclNullableSliceNull()->s32
    {
        if var x: #null [..] s32 = null where x == null
        {
            return 1
        }
        return -1
    }

    const V = #run ifDeclNullableSliceNull()
    @assert(V == 1)
}
