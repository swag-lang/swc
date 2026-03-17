// 

#global fileprivate
 
func function(x: s32, y: s32 = 100)->s32
{
    @assert(x == 50)
    @assert(y == 100)
    return y
}

#test
{
    let ptr = &function
    @assert(ptr(50) == 100)
}
