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
    var first: NativeSparseDefaultFirstOwner
    var second: NativeSparseDefaultSecondOwner

    @assert(first.payload.leaves[0].marker == 0x123456789ABCDEF0)
    @assert(first.payload.leaves[7].marker == 0x123456789ABCDEF0)
    @assert(first.marker == 11)
    @assert(second.payload.leaves[0].marker == 0x123456789ABCDEF0)
    @assert(second.payload.leaves[7].marker == 0x123456789ABCDEF0)
    @assert(second.marker == 17)
}
