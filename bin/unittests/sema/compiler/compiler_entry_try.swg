#global fileprivate

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
    g_State += value
}

#main
{
    try mayThrowVoid()
    let value = try mayThrowValue(100)
    g_State += value
}

#drop
{
    try mayThrowVoid()
}
