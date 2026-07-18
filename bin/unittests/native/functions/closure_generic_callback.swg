#global private
#global #[Swag.ExplicitNullability]

#test
{
    var result: ClosureGenericCallbackSupport.ByteSet = {values: ['C''u8, 'A''u8, 'B''u8, 0], count: 3}
    @assert(ClosureGenericCallbackSupport.invokeUnary('C''u8, func|&result|(x: u8)->bool { return result.contains(x) }))
    @assert(!ClosureGenericCallbackSupport.invokeUnary('Z''u8, func|&result|(x: u8)->bool { return result.contains(x) }))
}

#test
{
    var result: ClosureGenericCallbackSupport.ByteSet = {values: ['C''u8, 'A''u8, 'B''u8, 0], count: 3}
    @assert(ClosureGenericCallbackSupport.invokeGeneric('A''u8, func|&result|(x: u8)->bool { return result.contains(x) }))
    @assert(!ClosureGenericCallbackSupport.invokeGeneric('Z''u8, func|&result|(x: u8)->bool { return result.contains(x) }))
}

#test
{
    var prev:   [3] u8 = ['C', 'A', 'B']
    var result: ClosureGenericCallbackSupport.ByteSet = {values: ['A''u8, 'B''u8, 'C''u8, 'D''u8], count: 4}
    @assert(ClosureGenericCallbackSupport.allOf(prev[ to ], func|&result|(x: u8)->bool { return result.contains(x) }))
}
