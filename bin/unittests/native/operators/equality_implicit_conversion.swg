#global private

struct EqualityPoint
{
    x, y: s32
}

// Equality reads both operands, so the same const qualification accepted by an
// assignment must also be accepted by the comparison in either direction.
#test
{
    var mutableBytes: [4] u8        = [1, 2, 3, 4]
    let mutableView:  [..] u8       = mutableBytes
    let readOnlyView: const [..] u8 = mutableBytes

    @assert(mutableView == readOnlyView)
    @assert(readOnlyView == mutableView)
    @assert(mutableView == [1'u8, 2'u8, 3'u8, 4'u8])
    @assert([1'u8, 2'u8, 3'u8, 4'u8] == readOnlyView)

    let missing: #null const [..] u8 = null
    @assert(missing != mutableView)
    @assert(mutableView != missing)
}

// Fixed arrays follow the same read-only qualification rule.
#test
{
    var mutableArray:  [4] u8       = [1, 2, 3, 4]
    let readOnlyArray: const [4] u8 = mutableArray
    @assert(mutableArray == readOnlyArray)
    @assert(readOnlyArray == mutableArray)
}

// Reference normalization must happen before a structure literal is contextualized.
#test
{
    var point = EqualityPoint{10, 20}
    let pointRef: const *EqualityPoint = &point
    @assert(pointRef[] == {10, 20})
    @assert({10, 20} == pointRef[])
}
