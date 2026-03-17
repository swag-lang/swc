// 

#global fileprivate
 
func function(x: s32, y: ...)->u64
{
    @assert(x == 50)
    return @countof(y)
}

#test
{
    let ptr = &function
    @assert(ptr(50) == 0)
}
