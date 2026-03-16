#global fileprivate // swc-option suite-test

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
    @assert(GAddOne(41) == 42)
    @assert(GMulTwo(21) == 42)
}

