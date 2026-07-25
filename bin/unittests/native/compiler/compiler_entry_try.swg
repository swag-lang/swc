#global private

func mayFailVoid() fail {}

func mayFailValue(value: s32)->s32 fail
{
    return value
}

var g_State: s32

#init
{
    try mayFailVoid()
    g_State += 1
}

#premain
{
    let value = try mayFailValue(10)
    @assert(value == 10)
    g_State += value
}

#test
{
    @assert(g_State == 11)
}

#drop
{
    try mayFailVoid()
    @assert(g_State == 11)
}
