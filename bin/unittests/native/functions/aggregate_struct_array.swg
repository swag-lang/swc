#global private

func aggregateStructArrayDigits(payloadIndex: u64) -> s32
{
    let payloads = [
        {values: [1, 2, 3], bias: 4},
        {values: [9, 8, 7], bias: 5},
    ]

    let payload = payloads[payloadIndex]
    var digits: s32 = 0
    for value in payload.values
    {
        digits = digits * 10 + value
    }

    return digits + payload.bias
}

func aggregateStructArrayMiddle(payloadIndex: u64) -> s32
{
    let payloads = [
        {values: [5, 4, 3, 2], bias: 7},
        {values: [6, 1, 8, 9], bias: 3},
    ]

    let payload = payloads[payloadIndex]
    return payload.values[1] * 10 + payload.values[2] + payload.bias
}

#test
{
    @assert(aggregateStructArrayDigits(0) == 127)
    @assert(aggregateStructArrayDigits(1) == 992)
    @assert(aggregateStructArrayMiddle(1) == 21)
}
