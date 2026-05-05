#global fileprivate

func(T) genericIdentity(value: T)->T => value

#test
{
    let payload = genericIdentity({values: [9, 4, 1], bias: 1})
    let idx = 1

    #assert(#typeof(payload.values) == [3] s32)
    @assert(payload.values[idx] + payload.bias == 5)
}
