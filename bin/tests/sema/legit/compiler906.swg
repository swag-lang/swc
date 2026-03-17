#global fileprivate // swc-option sema-only
#global skip
func arithmeticMean(x: f64)
{
    @assert(x == 1.0)
}

#test
{
    arithmeticMean(1.0)
}
