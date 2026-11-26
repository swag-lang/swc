#test
{
    var value: f32 = 1.5
    let sum        = crossFileAddRefValue(&value, 2.5_f32)
    let temp       = crossFileDampRefValue(&value, 2.0_f32, 3.0_f32, 0.5_f32)

    #assert(#typeof(sum) == f32)
    #assert(#typeof(temp) == f32)
    Swag.require(sum == 4.0_f32)
    Swag.require(temp == 3.75_f32)
}

#test
{
    var box: CrossFileRefFloatBox = CrossFileRefFloatBox{value: 1.5}
    let sum  = crossFileAddRefValue(&box.value, 2.5_f32)
    let temp = crossFileDampRefValue(&box.value, 2.0_f32, 3.0_f32, 0.5_f32)

    #assert(#typeof(sum) == f32)
    #assert(#typeof(temp) == f32)
    Swag.require(sum == 4.0_f32)
    Swag.require(temp == 3.75_f32)
}
