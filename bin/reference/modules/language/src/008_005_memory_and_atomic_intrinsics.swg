#global private

/**
# Raw Memory

'Swag.memcpy' copies non-overlapping bytes, 'Swag.memmove' supports overlap, 'Swag.memset'
writes one byte value repeatedly, and 'Swag.memcmp' compares byte sequences. Counts
are expressed in bytes.
*/
#test
{
    var source      = [1'u8, 2, 3, 4]
    var destination = [0'u8, 0, 0, 0]

    Swag.memcpy(&destination[0], &source[0], source.count)
    Swag.assert(Swag.memcmp(&destination[0], &source[0], source.count) == 0)

    Swag.memmove(&destination[1], &destination[0], 3)
    Swag.assert(destination[0] == 1 and destination[1] == 1)
    Swag.assert(destination[2] == 2 and destination[3] == 3)

    Swag.memset(&destination[0], 0'u8, destination.count)
    Swag.assert(destination[0] == 0 and destination[1] == 0)
    Swag.assert(destination[2] == 0 and destination[3] == 0)
}

/**
# Atomic Read-Modify-Write

Atomic intrinsics update an integer through a pointer and return its **previous**
value. The family includes add, bitwise and/or/xor, exchange, and compare-
exchange.
*/
#test
{
    var counter = 10's32

    let beforeAdd = Swag.atomadd(&counter, 5)
    Swag.assert(beforeAdd == 10 and counter == 15)

    let beforeExchange = Swag.atomxchg(&counter, 20)
    Swag.assert(beforeExchange == 15 and counter == 20)

    let beforeCompareExchange = Swag.atomcmpxchg(&counter, 20, 30)
    Swag.assert(beforeCompareExchange == 20 and counter == 30)
}

/**
> WARNING:
> Raw memory operations bypass 'opPostCopy', 'opPostMove', and 'opDrop'. Do not
> use them to copy or relocate lifecycle-bearing values unless the type's
> invariants explicitly permit it.
*/
