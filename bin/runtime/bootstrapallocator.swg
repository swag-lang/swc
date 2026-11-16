// System allocation used before the normal runtime allocator can reach its thread context.
// Each allocation owns a host-page reservation so this layer needs no process heap or C runtime.

internal struct BootstrapAllocationHeader
{
    base:         *void?
    reservedSize: u64
}

internal const BootstrapAllocationHeaderSize = #sizeof(BootstrapAllocationHeader)

internal func __bootstrapRoundedSize(size: u64, alignment: u32)->u64
{
    if alignment == 0 or (alignment & (alignment - 1)) != 0 do
        return 0

    let effectiveAlignment = Swag.max(alignment, cast(u32, #alignof(BootstrapAllocationHeader)))
    let alignment64        = cast(u64, effectiveAlignment)
    var overhead: u64      = BootstrapAllocationHeaderSize
    if cast(u64, effectiveAlignment) <= AllocatorHostCommitGranularity
    {
        // Host reservations start on a commit-granularity boundary, so alignments up to
        // that size need only the rounded header prefix, not worst-case padding.
        overhead = (overhead + alignment64 - 1) & ~(alignment64 - 1)
    }
    else
    {
        overhead += alignment64 - 1
    }

    if size > Swag.U64.Max - overhead do
        return 0

    let total = size + overhead
    if total > Swag.U64.Max - (AllocatorHostCommitGranularity - 1) do
        return 0
    return (total + AllocatorHostCommitGranularity - 1) & ~(AllocatorHostCommitGranularity - 1)
}

internal func __bootstrapAllocAligned(size: u64, alignment: u32)->[*] void?
{
    if alignment == 0 or (alignment & (alignment - 1)) != 0 do
        return null

    let effectiveAlignment = Swag.max(alignment, cast(u32, #alignof(BootstrapAllocationHeader)))
    let reservedSize       = __bootstrapRoundedSize(size, effectiveAlignment)
    if not reservedSize do
        return null

    let base = __hostPageReserve(reservedSize)
    if not base do
        return null
    if not __hostPageCommit(base, reservedSize)
    {
        __hostPageRelease(base, reservedSize)
        return null
    }

    let alignment64          = cast(u64, effectiveAlignment)
    let unalignedUserAddress = cast(u64, base) + BootstrapAllocationHeaderSize
    let userAddress          = (unalignedUserAddress + alignment64 - 1) & ~(alignment64 - 1)
    let header      = cast(*BootstrapAllocationHeader, userAddress - BootstrapAllocationHeaderSize)
    header.base         = base
    header.reservedSize = reservedSize
    return cast([*] void, userAddress)
}

internal func __bootstrapAlloc(size: u64)->[*] void? => __bootstrapAllocAligned(size, cast(u32, #alignof(*void)))

internal func __bootstrapFree(ptr: [*] void?)
{
    if not ptr do
        return

    let header = cast(*BootstrapAllocationHeader, (cast(u64, ptr) - BootstrapAllocationHeaderSize))
    __hostPageRelease(header.base, header.reservedSize)
}
