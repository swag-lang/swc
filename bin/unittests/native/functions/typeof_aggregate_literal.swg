#global private
#global #[Swag.ExplicitNullability]

func typeofStructLiteralField(valueIndex: u64)->s32
{
    #assert(#typeof({values: [9, 4, 1], bias: 1}.values) == const [3] s32)
    let payload = {values: [9, 4, 1], bias: 1}
    return payload.values[valueIndex] + payload.bias
}

#test
{
    @assert(typeofStructLiteralField(0) == 10)
    @assert(typeofStructLiteralField(2) == 2)
}
