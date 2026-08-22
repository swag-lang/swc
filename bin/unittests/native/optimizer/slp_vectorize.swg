#global private
using Swag

// Superword-level auto-vectorization regression coverage. Every function is
// forced to the optimizing backend; in build configurations that vectorize,
// the adjacent 32-bit store groups below become packed code, and the asserted
// results must match the scalar semantics either way. The ChaCha20 round structure is the reference
// workload: interleaved add/xor/rotate lanes, store-forwarded reloads, and
// the diagonal rounds that exercise the lane-permutation path.

#[Swag.Inline]
func add32(left, right: u32)->u32 => cast(u32) ((cast(u64) left + right) & 0xFFFF_FFFF)

#[Swag.Inline]
func quarterRound(state: *[16] u32, a, b, c, d: u32)
{
    state[][a] = add32(state[][a], state[][b])
    state[][d] ^= state[][a]
    state[][d] = @rol(state[][d], 16)
    state[][c] = add32(state[][c], state[][d])
    state[][b] ^= state[][c]
    state[][b] = @rol(state[][b], 12)
    state[][a] = add32(state[][a], state[][b])
    state[][d] ^= state[][a]
    state[][d] = @rol(state[][d], 8)
    state[][c] = add32(state[][c], state[][d])
    state[][b] ^= state[][c]
    state[][b] = @rol(state[][b], 7)
}

// The state array arrives through a pointer, so the vectorizer sees a
// parameter-rooted store group.
#[Swag.Optimize(true)]
func chachaRounds(state: *[16] u32)
{
    for 10
    {
        quarterRound(state, 0, 4, 8, 12)
        quarterRound(state, 1, 5, 9, 13)
        quarterRound(state, 2, 6, 10, 14)
        quarterRound(state, 3, 7, 11, 15)
        quarterRound(state, 0, 5, 10, 15)
        quarterRound(state, 1, 6, 11, 12)
        quarterRound(state, 2, 7, 8, 13)
        quarterRound(state, 3, 4, 9, 14)
    }
}

// The same rounds over a local array: the store groups sit on the frame.
#[Swag.Optimize(true)]
func chachaRoundsLocal()->u32
{
    var state: [16] u32
    for i in 16 do
        state[i] = cast(u32) (i * 0x01010101)

    for 10
    {
        quarterRound(&state, 0, 4, 8, 12)
        quarterRound(&state, 1, 5, 9, 13)
        quarterRound(&state, 2, 6, 10, 14)
        quarterRound(&state, 3, 7, 11, 15)
        quarterRound(&state, 0, 5, 10, 15)
        quarterRound(&state, 1, 6, 11, 12)
        quarterRound(&state, 2, 7, 8, 13)
        quarterRound(&state, 3, 4, 9, 14)
    }

    var acc = 0'u32
    for i in 16 do
        acc ^= state[i]
    return acc
}

// A lane group whose stored values are read back immediately with a live
// consumer: whether the group is vectorized or the deletion safety check
// refuses it, the read must see the freshly stored value.
#[Swag.Optimize(true)]
func lanesThenReadBack(values: *[8] u32)->u32
{
    values[][4] = values[][0] + 1
    values[][5] = values[][1] + 1
    values[][6] = values[][2] + 1
    values[][7] = values[][3] + 1
    return values[][5]
}

// An incomplete chunk: three adjacent stores never form a packed group and
// must stay scalar.
#[Swag.Optimize(true)]
func threeLanes(values: *[8] u32)
{
    values[][4] = values[][0] + 1
    values[][5] = values[][1] + 1
    values[][6] = values[][2] + 1
}

#test
{
    var state: [16] u32
    for i in 16 do
        state[i] = cast(u32) (i * 0x01010101)
    chachaRounds(&state)

    // Reference values from an independent scalar implementation of the same
    // 20 ChaCha rounds over this seed pattern.
    const Expected: [16] u32 = [
        0xFE5B380F, 0x0E67C12B, 0xCB991485, 0x0F7CDEF6,
        0x3D381414, 0x7C02A81A, 0x67490CA5, 0xEC264FC3,
        0x2A598CB0, 0xBCDF0F50, 0xA0FF67B6, 0x1E1813E1,
        0x6E6F2414, 0x3611BE53, 0x90B57CBF, 0x885F04F2]
    for i in 16 do
        @assert(state[i] == Expected[i])
}

#test
{
    @assert(chachaRoundsLocal() == 0x9679D982)
}

#test
{
    var values: [8] u32 = [10, 20, 30, 40, 0, 0, 0, 0]
    @assert(lanesThenReadBack(&values) == 21)
    @assert(values[4] == 11 and values[5] == 21 and values[6] == 31 and values[7] == 41)
}

#test
{
    var values: [8] u32 = [10, 20, 30, 40, 0, 0, 0, 99]
    threeLanes(&values)
    @assert(values[4] == 11 and values[5] == 21 and values[6] == 31 and values[7] == 99)
}
