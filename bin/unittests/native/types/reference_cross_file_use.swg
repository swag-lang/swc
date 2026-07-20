#test
{
    var value: f32 = 1.5
    let sum = crossFileAddRefValue(&value, 2.5'f32)
    let temp = crossFileDampRefValue(&value, 2.0'f32, 3.0'f32, 0.5'f32)

    #assert(#typeof(sum) == f32)
    #assert(#typeof(temp) == f32)
    @assert(sum == 4.0'f32)
    @assert(temp == 3.75'f32)
}

#test
{
    var box: CrossFileRefFloatBox = {value: 1.5}
    let sum = crossFileAddRefValue(&box.value, 2.5'f32)
    let temp = crossFileDampRefValue(&box.value, 2.0'f32, 3.0'f32, 0.5'f32)

    #assert(#typeof(sum) == f32)
    #assert(#typeof(temp) == f32)
    @assert(sum == 4.0'f32)
    @assert(temp == 3.75'f32)
}
