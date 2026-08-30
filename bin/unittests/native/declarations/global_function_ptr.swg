#global private

alias UnaryFn = func(s32)->s32

func addOne(value: s32)->s32
{
    return value + 1
}

func mulTwo(value: s32)->s32
{
    return value * 2
}

var GAddOne: UnaryFn = &addOne
var GMulTwo: UnaryFn = &mulTwo

#test
{
    Swag.assert(GAddOne(41) == 42)
    Swag.assert(GMulTwo(21) == 42)
}
