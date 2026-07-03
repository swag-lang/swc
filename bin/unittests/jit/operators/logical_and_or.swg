#global private
var LogCounter: s32

func sideEffect(flag: bool, delta: s32)->bool
{
    LogCounter += delta
    return flag
}

func logicalValueProbe(value: s64, delta: s32)->s64
{
    LogCounter += delta
    return value
}

func logicalFloatProbe(value: f32, delta: s32)->f32
{
    LogCounter += delta
    return value
}

#test
{
    LogCounter = 0
    let value = logicalValueProbe(3, 1) or sideEffect(true, 10)
    @assert(value)
    @assert(LogCounter == 1)
}

#test
{
    LogCounter = 0
    let value = logicalValueProbe(0, 1) and sideEffect(true, 10)
    @assert(!value)
    @assert(LogCounter == 1)
}

#test
{
    LogCounter = 0
    let value = logicalValueProbe(0, 1) or sideEffect(true, 10)
    @assert(value)
    @assert(LogCounter == 11)
}

#test
{
    LogCounter = 0
    let value = logicalFloatProbe(0.0'f32, 1) or sideEffect(true, 10)
    @assert(value)
    @assert(LogCounter == 11)
}

#test
{
    LogCounter = 0
    let value = logicalFloatProbe(2.0'f32, 1) or sideEffect(true, 10)
    @assert(value)
    @assert(LogCounter == 1)
}

#test
{
    LogCounter = 0
    let value = logicalValueProbe(2, 1) and sideEffect(true, 10)
    @assert(value)
    @assert(LogCounter == 11)
}
