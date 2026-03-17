// 

#global fileprivate
#test
{
    @assert(#sizeof(*bool) == 8)
    @assert(#sizeof(1's32) == 4)
    @assert(#sizeof(1'u64) == 8)
    @assert(#sizeof(1.0'f32) == 4)
    @assert(#sizeof(1.0'f64) == 8)
    @assert(#sizeof(5 * 4's32) == 4)
}
