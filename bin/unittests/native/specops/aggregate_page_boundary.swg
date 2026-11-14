#global private

#[Swag.NoInline, Swag.Optimize(true)]
func(N: s32) equalAtPageEnd(left, right: const *[N]u8)->bool => left[] == right[]

#[Swag.NoInline, Swag.Optimize(true)]
func(N: s32) readAtPageEnd(value: const *[N]u8)->[N]u8 => value[]

func(N: s32) checkGuardedSize()
{
    var allocator: Swag.Allocator
    allocator.setup()
    const PageSize = Swag.AllocatorCommitGranularity
    let leftPages = unwrap allocator.osAllocPartial(2 * PageSize, PageSize)
    defer allocator.osFree(leftPages, 2 * PageSize, PageSize)
    let rightPages = unwrap allocator.osAllocPartial(2 * PageSize, PageSize)
    defer allocator.osFree(rightPages, 2 * PageSize, PageSize)
    let left  = cast(*[N]u8, leftPages + PageSize - N)
    let right = cast(*[N]u8, rightPages + PageSize - N)
    for index in N
    {
        left[][index]  = cast(u8, index + 10)
        right[][index] = left[][index]
    }

    Swag.require(equalAtPageEnd(left, right))
    let returned = readAtPageEnd(left)
    for index in N do
        Swag.require(returned[index] == right[][index])
    for mismatch in N
    {
        right[][mismatch] ^= 1
        Swag.require(not equalAtPageEnd(left, right))
        right[][mismatch] ^= 1
    }
}

// Both arrays end exactly at an inaccessible page: a rounded-up load must fault.
#test
{
    checkGuardedSize'(1)()
    checkGuardedSize'(2)()
    checkGuardedSize'(3)()
    checkGuardedSize'(4)()
    checkGuardedSize'(5)()
    checkGuardedSize'(6)()
    checkGuardedSize'(7)()
    checkGuardedSize'(8)()
    checkGuardedSize'(9)()
    checkGuardedSize'(15)()
    checkGuardedSize'(16)()
    checkGuardedSize'(17)()
    checkGuardedSize'(31)()
}
