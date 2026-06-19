#global fileprivate

func mixedNumericArraySum() -> f64
{
    let values = [1, 2.5]
    #assert(#typeof(values[0]) == f32)
    #assert(#typeof(values[1]) == f32)
    return cast(f64) values[0] + cast(f64) values[1]
}

#test
{
    const value = #run mixedNumericArraySum()
    #assert(value == 3.5)
}
