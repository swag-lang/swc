#global private

func inferredMixedArray() => [1, 2.5]
func inferredWideArray() => [1, 5_000_000_000]

func useInferredMixedArray()->bool
{
    let arr = inferredMixedArray()
    let idx = 1
    return arr[0] == 1.0'f32 and arr[idx] == 2.5'f32
}

func useInferredWideArray()->bool
{
    let arr = inferredWideArray()
    let idx = 1
    return arr[0] == 1's64 and arr[idx] == 5_000_000_000's64
}

#test
{
    const mixedOk = #run useInferredMixedArray()
    const wideOk  = #run useInferredWideArray()
    #assert(mixedOk)
    #assert(wideOk)
}
