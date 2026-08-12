#global private

/**
# Raw Memory

'@memcpy' copies non-overlapping bytes, '@memmove' supports overlap, '@memset'
writes one byte value repeatedly, and '@memcmp' compares byte sequences. Counts
are expressed in bytes.
*/
#test
{
    var source      = [1'u8, 2, 3, 4]
    var destination = [0'u8, 0, 0, 0]

    @memcpy(&destination[0], &source[0], @countof(source))
    @assert(@memcmp(&destination[0], &source[0], @countof(source)) == 0)

    @memmove(&destination[1], &destination[0], 3)
    @assert(destination[0] == 1 and destination[1] == 1)
    @assert(destination[2] == 2 and destination[3] == 3)

    @memset(&destination[0], 0'u8, @countof(destination))
    @assert(destination[0] == 0 and destination[1] == 0)
    @assert(destination[2] == 0 and destination[3] == 0)
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

    let beforeAdd = @atomadd(&counter, 5)
    @assert(beforeAdd == 10 and counter == 15)

    let beforeExchange = @atomxchg(&counter, 20)
    @assert(beforeExchange == 15 and counter == 20)

    let beforeCompareExchange = @atomcmpxchg(&counter, 20, 30)
    @assert(beforeCompareExchange == 20 and counter == 30)
}

/**
> WARNING:
> Raw memory operations bypass 'opPostCopy', 'opPostMove', and 'opDrop'. Do not
> use them to copy or relocate lifecycle-bearing values unless the type's
> invariants explicitly permit it.
*/
