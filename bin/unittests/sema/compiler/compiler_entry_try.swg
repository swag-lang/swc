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
    g_State += value
}

#main
{
    try mayFailVoid()
    let value = try mayFailValue(100)
    g_State += value
}

#drop
{
    try mayFailVoid()
}
