#global private

func freeStructLiteralDigits()->s32
{
    let payload = {values: [1, 2, 3, 4], tag: 5}
    var digits: s32 = 0
    for value in payload.values
    {
        digits = digits * 10 + value
    }

    return digits + payload.tag
}

func freeStructLiteralTail()->s32
{
    let payload = {values: [4, 6, 8, 9], tag: 3}
    return payload.values[3] * 10 + payload.tag
}

#test
{
    const value = #run freeStructLiteralDigits()
    #assert(value == 1239)
}

#test
{
    const value = #run freeStructLiteralTail()
    #assert(value == 93)
}
