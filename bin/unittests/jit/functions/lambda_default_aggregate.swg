#global private

#test
{
    let cb = func(values = [1, 2.5])->f32
    {
        return values[0] + values[1]
    }

    Swag.require(cb() == 3.5)
    Swag.require(cb([5.0, 1.5]) == 6.5)
}

#test
{
    let cb = func(payload = {values: [3, 4, 5], bias: 7})->s32
    {
        return payload.values[0] + payload.values[2] + payload.bias
    }

    Swag.require(cb() == 15)
    Swag.require(cb({values: [10, 20, 30], bias: 4}) == 44)
}
