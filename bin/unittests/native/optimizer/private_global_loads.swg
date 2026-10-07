#global private

// A scalar or pointer global whose address no use binds can only change through its own direct
// stores or a call, so a loop that writes through pointers may keep it in a register. Every
// other way of reaching it must still be observed.

var g_TableStorage: [64] u64
var g_PrivateTable: [*] u64?
var g_PrivateCount: u64

var g_TakenCount:   u64
var g_TakenAddress: *u64?

var g_DirectCount: u64
var g_CalledCount: u64

#[Swag.NoInline]
func takeCountAddress() { g_TakenAddress = &g_TakenCount }

#[Swag.NoInline]
func bumpCalledCount() { g_CalledCount += 1 }

// Pointer stores in the loop; the table and the count are private and stay invariant.
#[Swag.NoInline]
func fillPrivateTable()->u64
{
    var sum = 0'u64
    for i in 64
    {
        g_PrivateTable![i] = cast(u64) i * 3
        if i < g_PrivateCount do
            sum += g_PrivateTable![i]
    }
    return sum
}

// The address escaped in another function: a store through any pointer may be that global.
#[Swag.NoInline]
func countThroughEscapedAddress(slots: [*] u64, target: *u64)->u64
{
    var seen = 0'u64
    for i in 8
    {
        target[] = cast(u64) i + 100
        slots[i] = g_TakenCount
        seen     += g_TakenCount
    }
    return seen
}

// A direct read-modify-write of the global inside the loop must be read back every time.
#[Swag.NoInline]
func countDirectWrites(slots: [*] u64)->u64
{
    var seen = 0'u64
    for i in 8
    {
        slots[i]      = g_DirectCount
        g_DirectCount += 2
        seen          += g_DirectCount
    }
    return seen
}

// A call may write the global.
#[Swag.NoInline]
func countAcrossCalls(slots: [*] u64)->u64
{
    var seen = 0'u64
    for i in 8
    {
        slots[i] = g_CalledCount
        bumpCalledCount()
        seen += g_CalledCount
    }
    return seen
}

#test
{
    g_PrivateTable = &g_TableStorage[0]
    g_PrivateCount = 10
    Swag.assert(fillPrivateTable() == 135)

    var slots: [8] u64
    takeCountAddress()
    g_TakenCount = 0
    Swag.assert(countThroughEscapedAddress(&slots[0], g_TakenAddress!) == 828)
    Swag.assert(slots[7] == 107)

    g_DirectCount = 1
    Swag.assert(countDirectWrites(&slots[0]) == 80)
    Swag.assert(slots[7] == 15)

    g_CalledCount = 0
    Swag.assert(countAcrossCalls(&slots[0]) == 36)
    Swag.assert(slots[7] == 7)

    g_PrivateCount = 13
    var target = 0'u64
    Swag.assert(readPrivateAroundStores(&target, false) == 26)
    Swag.assert(target == 20 and g_DirectCount == 99)
    Swag.assert(readPrivateAroundStores(&target, true) == 26)
    Swag.assert(target == 24)
    g_CalledCount = 0
    var laterSlots: [4] u64
    Swag.assert(readBeforeLaterCall(&laterSlots[0]) == 6)
    Swag.assert(laterSlots[0] == 0 and laterSlots[3] == 3 and g_CalledCount == 4)
}

// A straight-line pointer store and a write of another private global do not
// invalidate this cell. Both branch outcomes must still observe the writes.
#[Swag.NoInline]
func readPrivateAroundStores(target: *u64, alternate: bool)->u64
{
    let before = g_PrivateCount
    target[]      = before + 7
    g_DirectCount = 99
    if alternate do target[] = before + 11
    return before + g_PrivateCount
}

// The call follows both reads in source order, but reaches them on the next trip.
#[Swag.NoInline]
func readBeforeLaterCall(slots: [*] u64)->u64
{
    var sum = 0'u64
    for i in 4
    {
        slots[i] = g_CalledCount
        sum      += g_CalledCount
        bumpCalledCount()
    }
    return sum
}
