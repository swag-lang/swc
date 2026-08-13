struct CrossFileRefFloatBox
{
    value: f32
}

func(T) crossFileAddRefValue(value: *T, rhs: T)->T
{
    return dref value + rhs
}

func(T) crossFileDampRefValue(currentVelocity: *T, omega, clampedChange, deltaTime: T)->T
{
    let temp = (dref currentVelocity + omega * clampedChange) * deltaTime
    return temp
}
