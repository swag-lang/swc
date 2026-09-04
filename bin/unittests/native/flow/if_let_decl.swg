#global private

func nativeRetNothing()->string? => null

func nativeIfLetSimple()->s32
{
    if let x = 1
    {
        return x
    }
    else
    {
        return x + 10
    }
}

func nativeIfLetWhereFalseElse()->s32
{
    if let x = 1 where false
    {
        return -1
    }
    else
    {
        return x + 2
    }
}

func nativeIfLetDo()->s32
{
    if let x = 4 where x > 2 do
        return x + 1

    return -1
}

func nativeIfLetNullableNullElse()->s32
{
    if let str = nativeRetNothing()
    {
        return -1
    }

    return 1
}

func nativeIfLetNullableWhereSkip()->s32
{
    if let str = nativeRetNothing() where str[0] == 's'
    {
        return -1
    }

    return 1
}

#test
{
    Swag.assert(nativeIfLetSimple() == 1)
}

#test
{
    Swag.assert(nativeIfLetWhereFalseElse() == 3)
}

#test
{
    Swag.assert(nativeIfLetDo() == 5)
}

#test
{
    Swag.assert(nativeIfLetNullableNullElse() == 1)
}

#test
{
    Swag.assert(nativeIfLetNullableWhereSkip() == 1)
}
