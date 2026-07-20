#global private

func freeStructLiteralLookup(valueIndex: u64) -> s32
{
    let payload = {values: [9, 4, 1], bias: 1}
    return payload.values[valueIndex] + payload.bias
}

func freeStructLiteralMiddle() -> s32
{
    let payload = {values: [7, 2, 5, 8], tag: 6}
    return payload.values[1] * 10 + payload.values[2] + payload.tag
}

#test
{
    @assert(freeStructLiteralLookup(1) == 5)
    @assert(freeStructLiteralLookup(2) == 2)
    @assert(freeStructLiteralMiddle() == 31)
}
