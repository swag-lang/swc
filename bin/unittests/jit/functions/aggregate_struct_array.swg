#global private

func aggregateStructArrayLookup(payloadIndex: u64, valueIndex: u64)->s32
{
    let payloads = [
        {values: [9, 4, 1], bias: 1},
        {values: [2, 8, 3], bias: 4},
        ]

    return payloads[payloadIndex].values[valueIndex] + payloads[payloadIndex].bias
}

func aggregateStructArrayEdge(payloadIndex: u64)->s32
{
    let payloads = [
        {values: [7, 1, 5, 3], bias: 2},
        {values: [6, 9, 8, 4], bias: 1},
        ]

    return payloads[payloadIndex].values[0] * 10 + payloads[payloadIndex].values[3]
}

#test
{
    const value = #run aggregateStructArrayLookup(0, 1)
    #assert(value == 5)
}

#test
{
    const value = #run aggregateStructArrayLookup(1, 2)
    #assert(value == 7)
    #assert(#run aggregateStructArrayEdge(1) == 64)
}
