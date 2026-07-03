#global private

func mayThrowVoid() throw
{
}

func mayThrowValue(value: s32)->s32 throw
{
    return value
}

var g_State: s32

#init
{
    try mayThrowVoid()
    g_State += 1
}

#premain
{
    let value = try mayThrowValue(10)
    @assert(value == 10)
    g_State += value
}

#test
{
    @assert(g_State == 11)
}

#drop
{
    try mayThrowVoid()
    @assert(g_State == 11)
}
