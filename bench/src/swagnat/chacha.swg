const SIZE = 4194304'u64 // 32-bit words, sixteen mebibytes of key stream
const M32  = 0xFFFFFFFF'u64

// The rounds add modulo 2^32. Going through 64 bits keeps the addition inside
// the range every port of this benchmark can represent exactly, and keeps the
// overflow guard of the checked build configurations out of the measurement.
#[Swag.Inline]
func add32(left, right: u32)->u32 => cast(u32) ((cast(u64) left + right) & M32)

#[Swag.Inline]
func quarterRound(state: *[16] u32, a, b, c, d: u32)
{
    (dref state)[a] = add32((dref state)[a], (dref state)[b])
    (dref state)[d] ^= (dref state)[a]
    (dref state)[d] = @rol((dref state)[d], 16)
    (dref state)[c] = add32((dref state)[c], (dref state)[d])
    (dref state)[b] ^= (dref state)[c]
    (dref state)[b] = @rol((dref state)[b], 12)
    (dref state)[a] = add32((dref state)[a], (dref state)[b])
    (dref state)[d] ^= (dref state)[a]
    (dref state)[d] = @rol((dref state)[d], 8)
    (dref state)[c] = add32((dref state)[c], (dref state)[d])
    (dref state)[b] ^= (dref state)[c]
    (dref state)[b] = @rol((dref state)[b], 7)
}

#main
{
    // ---- data generation (not timed) ----
    let data = cast([*] u32) @alloc(SIZE * 4)!
    for [i] in SIZE do
        data[i] = cast(u32) (rnd() & M32)

    var key: [8] u32
    for [i] in 8 do
        key[i] = cast(u32) (rnd() & M32)

    var nonce: [3] u32
    for [i] in 3 do
        nonce[i] = cast(u32) (rnd() & M32)

    // ---- timed work ----
    let t0 = now()

    var initial: [16] u32
    initial[0] = 0x61707865
    initial[1] = 0x3320646E
    initial[2] = 0x79622D32
    initial[3] = 0x6B206574
    for [i] in 8 do
        initial[4 + i] = key[i]
    for [i] in 3 do
        initial[13 + i] = nonce[i]

    var offset  = 0'u64
    var counter = 1'u32
    while offset < SIZE
    {
        initial[12] = counter

        var state = initial
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

        for [i] in 16'u64 do
            data[offset + i] ^= add32(state[i], initial[i])

        offset += 16
        counter += 1
    }

    var check = 0'u64
    for [i] in SIZE do
        check ^= (cast(u64) data[i] + i) & M32

    let t1 = now()
    report(check, t0, t1)
}
