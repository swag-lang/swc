struct NativeSparseDefaultLeaf
{
    zeros:  [4096] u64
    marker: u64 = 0x123456789ABCDEF0
}

struct NativeSparseDefaultPayload
{
    leaves: [8] NativeSparseDefaultLeaf
}

struct NativeSparseDefaultFirstOwner
{
    payload: NativeSparseDefaultPayload
    marker:  u64 = 11
}

struct NativeSparseDefaultSecondOwner
{
    prefix:  [1024] u64
    payload: NativeSparseDefaultPayload
    marker:  u64 = 17
}

#test
{
    var first:  NativeSparseDefaultFirstOwner
    var second: NativeSparseDefaultSecondOwner

    Swag.assert(first.payload.leaves[0].marker == 0x123456789ABCDEF0)
    Swag.assert(first.payload.leaves[7].marker == 0x123456789ABCDEF0)
    Swag.assert(first.marker == 11)
    Swag.assert(second.payload.leaves[0].marker == 0x123456789ABCDEF0)
    Swag.assert(second.payload.leaves[7].marker == 0x123456789ABCDEF0)
    Swag.assert(second.marker == 17)
}
