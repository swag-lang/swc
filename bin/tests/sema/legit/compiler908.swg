#global fileprivate // swc-option sema-only
#global skip
func greater(x, y: f32) => x > y

#test
{
    @assert(greater(1, 2) == false)
    @assert(greater(2, 1) == true)
}
