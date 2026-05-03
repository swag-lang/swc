#global fileprivate

union(T) ValueOrPtr
{
    value: T
    ptr:   *T
}

func(T) takeValue(boxed: ValueOrPtr'T)->T
{
    return boxed.value
}

#test
{
    let value = takeValue({value: 10's32})
    #assert(#typeof(value) == s32)
    @assert(value == 10)    
}
