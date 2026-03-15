#global fileprivate

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

func runGlobalFunctionPointers()->bool
{
    return GAddOne(41) == 42 and GMulTwo(21) == 42
}

#test
{
    const ok = #run runGlobalFunctionPointers()
    #assert(ok)
}
