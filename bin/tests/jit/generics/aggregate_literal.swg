#global fileprivate

func(T, N: s32) genericArrayIdentity(values: [N] T)->[N] T => values

#test
{
    let values = genericArrayIdentity([1, 2.5])
    let idx = 1

    #assert(#typeof(values) == [2] f32)
    @assert(values[0] == 1.0'f32)
    @assert(values[idx] == 2.5'f32)
}
