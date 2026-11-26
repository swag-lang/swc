#global private

#test
{
    var result: ClosureGenericCallbackSupport.ByteSet = {values: ['C'_u8, 'A'_u8, 'B'_u8, 0], count: 3}
    Swag.require(ClosureGenericCallbackSupport.invokeUnary('C'_u8, func|&result|(x: u8)->bool { return result.contains(x) }))
    Swag.require(not ClosureGenericCallbackSupport.invokeUnary('Z'_u8, func|&result|(x: u8)->bool { return result.contains(x) }))
}

#test
{
    var result: ClosureGenericCallbackSupport.ByteSet = {values: ['C'_u8, 'A'_u8, 'B'_u8, 0], count: 3}
    Swag.require(ClosureGenericCallbackSupport.invokeGeneric('A'_u8, func|&result|(x: u8)->bool { return result.contains(x) }))
    Swag.require(not ClosureGenericCallbackSupport.invokeGeneric('Z'_u8, func|&result|(x: u8)->bool { return result.contains(x) }))
}

#test
{
    var prev:   [3] u8 = ['C', 'A', 'B']
    var result: ClosureGenericCallbackSupport.ByteSet = {values: ['A'_u8, 'B'_u8, 'C'_u8, 'D'_u8], count: 4}
    Swag.require(ClosureGenericCallbackSupport.allOf(prev[to], func|&result|(x: u8)->bool { return result.contains(x) }))
}
