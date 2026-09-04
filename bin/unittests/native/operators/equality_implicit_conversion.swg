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

    Swag.assert(mutableView == readOnlyView)
    Swag.assert(readOnlyView == mutableView)
    Swag.assert(mutableView == [1'u8, 2'u8, 3'u8, 4'u8])
    Swag.assert([1'u8, 2'u8, 3'u8, 4'u8] == readOnlyView)

    let missing: const [..] u8? = null
    Swag.assert(missing != mutableView)
    Swag.assert(mutableView != missing)
}

// Fixed arrays follow the same read-only qualification rule.
#test
{
    var mutableArray:  [4] u8       = [1, 2, 3, 4]
    let readOnlyArray: const [4] u8 = mutableArray
    Swag.assert(mutableArray == readOnlyArray)
    Swag.assert(readOnlyArray == mutableArray)
}

// Reference normalization must happen before a structure literal is contextualized.
#test
{
    var point = EqualityPoint{10, 20}
    let pointRef: const *EqualityPoint = &point
    Swag.assert(pointRef[] == {10, 20})
    Swag.assert({10, 20} == pointRef[])
}
