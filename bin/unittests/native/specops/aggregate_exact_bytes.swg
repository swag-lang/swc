#global private

struct(N: s32) Envelope
{
    payload:   [N] u8
    following: [8] u8
}

#[Swag.NoInline, Swag.Optimize(true)]
func(N: s32) equalPayload(left, right: const *Envelope'(N))->bool => left.payload == right.payload

#[Swag.NoInline, Swag.Optimize(true)]
func(N: s32) differentPayload(left, right: const *Envelope'(N))->bool => left.payload != right.payload

#[Swag.NoInline, Swag.Optimize(true)]
func(N: s32) returnedPayload(value: const *Envelope'(N))->[N] u8 => value.payload

func(N: s32) checkSize()
{
    var left:  Envelope'(N)
    var right: Envelope'(N)
    for index in N
    {
        left.payload[index]  = cast(u8, index + 10)
        right.payload[index] = left.payload[index]
    }

    for index in 8
    {
        left.following[index]  = 0xA5
        right.following[index] = 0x5A
    }

    Swag.require(equalPayload(&left, &right))
    Swag.require(not differentPayload(&left, &right))
    Swag.require(returnedPayload(&left) == right.payload)
    for mismatch in N
    {
        right.payload[mismatch] ^= 1
        Swag.require(not equalPayload(&left, &right))
        Swag.require(differentPayload(&left, &right))
        Swag.require(returnedPayload(&left) != right.payload)
        right.payload[mismatch] ^= 1
    }

    for index in 8
    {
        Swag.require(left.following[index] == 0xA5)
        Swag.require(right.following[index] == 0x5A)
    }
}

#test
{
    checkSize'(1)()
    checkSize'(2)()
    checkSize'(3)()
    checkSize'(4)()
    checkSize'(5)()
    checkSize'(6)()
    checkSize'(7)()
    checkSize'(8)()
    checkSize'(9)()
    checkSize'(15)()
    checkSize'(16)()
    checkSize'(17)()
    checkSize'(31)()
}

#[Swag.Pack(1)]
struct PackedThree
{
    first: u16
    last:  u8
}

struct PackedEnvelope
{
    value:     PackedThree
    following: [8] u8
}

#[Swag.NoInline, Swag.Optimize(true)]
func equalPacked(left, right: const *PackedEnvelope)->bool => left.value == right.value

#[Swag.NoInline, Swag.Optimize(true)]
func makePacked(first: u16, last: u8)->PackedThree => {first: first, last: last}

#test
{
    var left:  PackedEnvelope = {value: {first: 0x1234, last: 0x56}, following: [0xA5'u8, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5]}
    var right: PackedEnvelope = {value: {first: 0x1234, last: 0x56}, following: [0x5A'u8, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A]}
    Swag.require(equalPacked(&left, &right))
    Swag.require(makePacked(0x1234, 0x56) == right.value)
    right.value.last ^= 1
    Swag.require(not equalPacked(&left, &right))
    Swag.require(makePacked(0x1234, 0x56) != right.value)
}
