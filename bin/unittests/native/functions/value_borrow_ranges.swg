#global private
#global #[Swag.Safety(.ValueBorrow, true)]

struct Small { bytes: [96] u8 }
struct Large { bytes: [2048] u8 }

#[Swag.NoInline]
func mutateSmall(value: Small, target: *Small, index: u64)->u8
{
    target.bytes[index] = 17
    return value.bytes[index]
}

#[Swag.NoInline]
func mutateLarge(value: Large, target: *Large, index: u64)->u8
{
    target.bytes[index] = 23
    return value.bytes[index]
}

// Both ends and internal boundaries remain protected regardless of stack alignment.
#test
{
    var value: Small
    for index in [0'u64, 63, 64, 95]
    {
        let caught = Swag.catchPanic(func|&value, index|() { discard mutateSmall(value, &value, index) })
        Swag.assert(caught.raised and value.bytes[index] == 0)
    }
    var other: Small
    Swag.assert(mutateSmall(value, &other, 95) == 0 and other.bytes[95] == 17)
    value.bytes[95] = 19
    Swag.assert(value.bytes[95] == 19)
}

// Ranges too wide for the small-range filter must still check every overlapping write.
#test
{
    var value: Large
    for index in [0'u64, 511, 512, 2047]
    {
        let caught = Swag.catchPanic(func|&value, index|() { discard mutateLarge(value, &value, index) })
        Swag.assert(caught.raised and value.bytes[index] == 0)
    }
    var other: Large
    Swag.assert(mutateLarge(value, &other, 2047) == 0 and other.bytes[2047] == 23)
    value.bytes[2047] = 29
    Swag.assert(value.bytes[2047] == 29)
}

#[Swag.NoInline]
func readInner(value: Small)->u8 => value.bytes[0]

#[Swag.NoInline]
func removeInner(value: Small, target: *Small)->u8
{
    Swag.assert(readInner(value) == value.bytes[0])
    target.bytes[0] = 31
    return value.bytes[0]
}

// Removing an overlapping inner borrow must retain the outer borrow's filter entries.
#test
{
    var value: Small
    let caught = Swag.catchPanic(func|&value|() { discard removeInner(value, &value) })
    Swag.assert(caught.raised and value.bytes[0] == 0)
}
