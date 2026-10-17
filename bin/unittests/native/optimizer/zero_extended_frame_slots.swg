#global private
using Swag

const M32 = 0xFFFFFFFF'u64

func rotr(x, k: u64)->u64 => ((x >> k) | (x << (32 - k))) & M32

// Every slot of `w` holds a 32-bit value, zero or masked, so a slot read back
// is already zero-extended and the schedule's rotations are 32-bit rotates.
#[Swag.Optimize(true), Swag.NoInline]
func schedule(seed: u64)->u64
{
    var head: [3] u64
    for t in 3 do
        head[t] = seed + t
    var w: [64] u64
    for t in 8 do
        w[t] = ((seed & 0xFFFFFF) * (t + 3)) & M32
    for t in 8 until 64
    {
        let x = w[t - 7]
        let y = w[t - 2]
        w[t] = (w[t - 8] + (rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)) + (rotr(y, 17) ^ (y >> 10))) & M32
    }

    var sum = head[0] ^ head[1] ^ head[2]
    for t in 64 do
        sum = ((sum << 5) | (sum >> 59)) ^ w[t]
    return sum
}

#[Swag.Optimize(false), Swag.NoInline]
func scheduleReference(seed: u64)->u64
{
    var head: [3] u64
    for t in 3 do
        head[t] = seed + t
    var w: [64] u64
    for t in 8 do
        w[t] = ((seed & 0xFFFFFF) * (t + 3)) & M32
    for t in 8 until 64
    {
        let x = w[t - 7]
        let y = w[t - 2]
        w[t] = (w[t - 8] + (rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)) + (rotr(y, 17) ^ (y >> 10))) & M32
    }

    var sum = head[0] ^ head[1] ^ head[2]
    for t in 64 do
        sum = ((sum << 5) | (sum >> 59)) ^ w[t]
    return sum
}

// The same schedule without the mask on the slots it computes: they carry
// bits above the low word, and the rotations read them.
#[Swag.Optimize(true), Swag.NoInline]
func scheduleUnmasked(seed: u64)->u64
{
    var head: [3] u64
    for t in 3 do
        head[t] = seed + t
    var w: [64] u64
    for t in 8 do
        w[t] = ((seed & 0xFFFFFF) * (t + 3)) & M32
    for t in 8 until 64
    {
        let x = w[t - 7]
        let y = w[t - 2]
        w[t] = (w[t - 8] + (rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)) + (rotr(y, 17) ^ (y >> 10)))
    }

    var sum = head[0] ^ head[1] ^ head[2]
    for t in 64 do
        sum = ((sum << 5) | (sum >> 59)) ^ w[t]
    return sum
}

#[Swag.Optimize(false), Swag.NoInline]
func scheduleUnmaskedReference(seed: u64)->u64
{
    var head: [3] u64
    for t in 3 do
        head[t] = seed + t
    var w: [64] u64
    for t in 8 do
        w[t] = ((seed & 0xFFFFFF) * (t + 3)) & M32
    for t in 8 until 64
    {
        let x = w[t - 7]
        let y = w[t - 2]
        w[t] = (w[t - 8] + (rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)) + (rotr(y, 17) ^ (y >> 10)))
    }

    var sum = head[0] ^ head[1] ^ head[2]
    for t in 64 do
        sum = ((sum << 5) | (sum >> 59)) ^ w[t]
    return sum
}

// One slot receives a whole 64-bit value: its read keeps the upper half the
// rotation shifts down.
#[Swag.Optimize(true), Swag.NoInline]
func rotateSlots(seed: u64)->u64
{
    var w: [4] u64
    w[0] = seed & M32
    w[1] = seed
    w[2] = seed >> 40
    var sum = 0'u64
    for t in 3 do
        sum = ((sum << 5) | (sum >> 59)) ^ rotr(w[t], 7)
    return sum
}

#[Swag.Optimize(false), Swag.NoInline]
func rotateSlotsReference(seed: u64)->u64
{
    var w: [4] u64
    w[0] = seed & M32
    w[1] = seed
    w[2] = seed >> 40
    var sum = 0'u64
    for t in 3 do
        sum = ((sum << 5) | (sum >> 59)) ^ rotr(w[t], 7)
    return sum
}

#test
{
    for seed in [0x12345678'u64, 0xFFFFFFFF, 0x0123456789ABCDEF, 0xFEDCBA9876543210]
    {
        Swag.assert(schedule(seed) == scheduleReference(seed))
        Swag.assert(scheduleUnmasked(seed) == scheduleUnmaskedReference(seed))
        Swag.assert(rotateSlots(seed) == rotateSlotsReference(seed))
    }
}
