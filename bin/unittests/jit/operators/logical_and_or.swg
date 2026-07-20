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

// A logical operator whose left operand is a live bool storage (a parameter or local)
// must not clobber that storage with the result of the whole expression.
func logicalKeepsLeftOperand(flag: bool)->bool
{
    let d = false
    let combined = flag and d
    return flag
}

#test
{
    // flag stays true even though 'flag and false' is false.
    @assert(logicalKeepsLeftOperand(true) == true)
    @assert(logicalKeepsLeftOperand(false) == false)

    var v = true
    let a = v and false
    @assert(v == true)

    var u = false
    let b = u or true
    @assert(u == false)
}
