#global private

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
    Swag.assert(V == 1)
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
    Swag.assert(V == 2)
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
    Swag.assert(V == 2)
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
    Swag.assert(V == 3)
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
    Swag.assert(V == 2)
}

#test
{
    func ifDeclMaybePtr(p: *s32)->*s32? => p

    func ifDeclNullablePointer()->s32
    {
        var base = 42
        if var x: *s32? = ifDeclMaybePtr(&base) where x != null
        {
            return 1
        }

        return -1
    }

    const V = #run ifDeclNullablePointer()
    Swag.assert(V == 1)
}

#test
{
    func ifDeclNullableStringNull()->s32
    {
        if var x: string? = null where x == null
        {
            return 1
        }
        return -1
    }

    const V = #run ifDeclNullableStringNull()
    Swag.assert(V == 1)
}

#test
{
    func ifDeclNullableSliceNull()->s32
    {
        if var x: [..] s32? = null where x == null
        {
            return 1
        }
        return -1
    }

    const V = #run ifDeclNullableSliceNull()
    Swag.assert(V == 1)
}

// 'if const' declarations must work in condition position.
#test
{
    func ifConstTruthy()->s32
    {
        if const a = 1 do
            return a
        else do
            return -1
    }

    const V = #run ifConstTruthy()
    Swag.assert(V == 1)
}

#test
{
    func ifConstFalsy()->s32
    {
        if const a = 0 do
            return -1
        else do
            return 42
    }

    const V = #run ifConstFalsy()
    Swag.assert(V == 42)
}
