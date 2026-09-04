// System allocation used before the normal runtime allocator can reach its thread context.
// Each allocation owns a host-page reservation so this layer needs no process heap or C runtime.

internal struct BootstrapAllocationHeader
{
    reservedSize: u64
    _padding:     u64
}

internal const BootstrapAllocationHeaderSize = #sizeof(BootstrapAllocationHeader)

internal func __bootstrapRoundedSize(size: u64)->u64
{
    if size > Swag.U64.Max - BootstrapAllocationHeaderSize do
        return 0

    let total = size + BootstrapAllocationHeaderSize
    if total > Swag.U64.Max - (AllocatorHostCommitGranularity - 1) do
        return 0
    return (total + AllocatorHostCommitGranularity - 1) & ~(AllocatorHostCommitGranularity - 1)
}

internal func __bootstrapAlloc(size: u64)->[*] void?
{
    let reservedSize = __bootstrapRoundedSize(size)
    if !reservedSize do
        return null

    let base = __hostPageReserve(reservedSize)
    if !base do
        return null
    if !__hostPageCommit(base, reservedSize)
    {
        __hostPageRelease(base, reservedSize)
        return null
    }

    let header = cast(*BootstrapAllocationHeader) base
    header.reservedSize = reservedSize
    header._padding     = 0
    return cast([*] void) (base + BootstrapAllocationHeaderSize)
}

internal func __bootstrapFree(ptr: [*] void?)
{
    if !ptr do
        return

    let base   = cast([*] u8) ptr! - BootstrapAllocationHeaderSize
    let header = cast(*BootstrapAllocationHeader) base
    __hostPageRelease(base, header.reservedSize)
}
