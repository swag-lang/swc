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

    Swag.require(first.payload.leaves[0].marker == 0x123456789ABCDEF0)
    Swag.require(first.payload.leaves[7].marker == 0x123456789ABCDEF0)
    Swag.require(first.marker == 11)
    Swag.require(second.payload.leaves[0].marker == 0x123456789ABCDEF0)
    Swag.require(second.payload.leaves[7].marker == 0x123456789ABCDEF0)
    Swag.require(second.marker == 17)
}
