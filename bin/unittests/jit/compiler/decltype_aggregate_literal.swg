#global private

var mixed: #decltype([1, 2.5]) = [1, 2.5]

#test
{
    let idx = 1

    #assert(#typeof(mixed[0]) == f32)
    #assert(#typeof(mixed[idx]) == f32)
    @assert(mixed[0] == 1.0'f32)
    @assert(mixed[idx] == 2.5'f32)
}
