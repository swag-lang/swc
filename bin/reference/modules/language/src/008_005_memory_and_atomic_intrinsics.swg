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
# Atomic Read

'Swag.atomget' reads an integer through a pointer as one atomic access. It is a plain
load on x86-64, so it takes no bus lock, and the compiler never hoists, merges, or drops
it: a loop polling a value that another thread publishes reads memory on every iteration.
*/
#test
{
    var flag = 0'u32
    Swag.assert(Swag.atomget(&flag) == 0)

    discard Swag.atomxchg(&flag, 1)
    Swag.assert(Swag.atomget(&flag) == 1)
}

/**
# Prefetch

'Swag.prefetch' tells the processor that the bytes at an address will be read soon, so
it can start bringing their cache line in while other work proceeds. It is a hint and
nothing more: it never faults, returns nothing, and changes no value the program can
observe. The address may be null, dangling, or one past the end of a buffer, and a target
without a prefetch instruction simply ignores the call. On x86-64 it is 'prefetcht0'.

A prefetch pays when it is issued well before the read, typically for the next item of
a loop whose address is known early, such as the reference rows a video decoder will
interpolate for the next block.
*/
#test
{
    const Width = 64
    var pixels: [4 * Width] u8
    var sum = 0'u32
    for row in 0 until 4
    {
        // Ask for the next row while this one is summed. The last hint points one past
        // the end of 'pixels', which is harmless.
        Swag.prefetch(pixels.buffer + (row + 1) * Width)
        for col in 0 until Width do
            sum += pixels[row * Width + col]
    }

    Swag.assert(sum == 0)
    Swag.prefetch(null)
}

/**
> WARNING:
> Raw memory operations bypass 'opPostCopy', 'opPostMove', and 'opDrop'. Do not
> use them to copy or relocate lifecycle-bearing values unless the type's
> invariants explicitly permit it.
*/
