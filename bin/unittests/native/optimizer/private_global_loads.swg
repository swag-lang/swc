#global private

// A scalar or pointer global whose address no use binds can only change through its own direct
// stores or a call, so a loop that writes through pointers may keep it in a register. Every
// other way of reaching it must still be observed.

var g_TableStorage: [64] u64
var g_PrivateTable: [*] u64?
var g_PrivateCount: u64

var g_TakenCount: u64
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
        seen += g_TakenCount
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
        slots[i] = g_DirectCount
        g_DirectCount += 2
        seen += g_DirectCount
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
}
