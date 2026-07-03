#global private

struct LambdaDefaultPayload
{
    values: [3] s32
    bias:   s32
}

alias LambdaDefaultArrayFn = func(values = [1, 2.5])->f32
alias LambdaDefaultPayloadFn = func(payload = {values: [3, 4, 5], bias: 7})->s32

#test
{
    let cb: LambdaDefaultArrayFn = func(values)->f32
    {
        var total = 0.0
        foreach value, index in values
        {
            total += value * cast(f32) index
        }

        return total + values[0]
    }

    @assert(cb() == 3.5)
    @assert(cb([2.0, 4.0]) == 6.0)
}

#test
{
    let cb: LambdaDefaultPayloadFn = func(payload)->s32
    {
        var total = payload.bias
        foreach value in payload.values do
            total += value
        return total
    }

    @assert(cb() == 19)
    @assert(cb({values: [9, 8, 7], bias: 2}) == 26)
}
