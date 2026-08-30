#global private

func typeofStructLiteralField(valueIndex: u64)->s32
{
    #assert(#typeof({values: [9, 4, 1], bias: 1}.values) == const [3] s32)
    let payload = {values: [9, 4, 1], bias: 1}
    return payload.values[valueIndex] + payload.bias
}

#test
{
    Swag.assert(typeofStructLiteralField(0) == 10)
    Swag.assert(typeofStructLiteralField(2) == 2)
}
