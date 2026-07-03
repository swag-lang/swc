#global #if #command == Swag.CompilerCommand.Test
#global private

struct FakeSync
{
    lockCount:         s32
    unlockCount:       s32
    sharedLockCount:   s32
    sharedUnlockCount: s32
    depth:             s32
    sharedDepth:       s32
}

impl FakeSync
{
    mtd lock()
    {
        .lockCount += 1
        .depth += 1
    }

    mtd unlock()
    {
        .unlockCount += 1
        .depth -= 1
    }

    mtd lockShared()
    {
        .sharedLockCount += 1
        .sharedDepth += 1
    }

    mtd unlockShared()
    {
        .sharedUnlockCount += 1
        .sharedDepth -= 1
    }
}

func scopedLockUnlocksAfterContinue()->bool
{
    var sync = FakeSync{}
    var reachedTail = 0

    for 4
    {
        Sync.scopedLock(&sync)
        if sync.depth != 1 do
            return false

        if @index != 3 do
            continue

        reachedTail += 1
    }

    return reachedTail == 1 and
        sync.lockCount == 4 and
        sync.unlockCount == 4 and
        sync.depth == 0
}

func scopedLockUnlocksAfterBreak()->bool
{
    var sync = FakeSync{}
    var seenInside = 0

    for 5
    {
        Sync.scopedLock(&sync)
        if sync.depth != 1 do
            return false

        seenInside += 1
        break
    }

    return seenInside == 1 and
        sync.lockCount == 1 and
        sync.unlockCount == 1 and
        sync.depth == 0
}

func scopedLockUnlocksAfterReturn()->bool
{
    var sync = FakeSync{}

    {
        Sync.scopedLock(&sync)
        if sync.depth != 1 do
            return false
        return true
    }
}

func sharedLockUnlocksAfterContinue()->bool
{
    var sync = FakeSync{}
    var reachedTail = 0

    for 3
    {
        Sync.sharedLock(&sync)
        if sync.sharedDepth != 1 do
            return false

        if @index != 2 do
            continue

        reachedTail += 1
    }

    return reachedTail == 1 and
        sync.sharedLockCount == 3 and
        sync.sharedUnlockCount == 3 and
        sync.sharedDepth == 0
}

#test
{
    @assert(scopedLockUnlocksAfterContinue())
    @assert(scopedLockUnlocksAfterBreak())
    @assert(scopedLockUnlocksAfterReturn())
    @assert(sharedLockUnlocksAfterContinue())
}
