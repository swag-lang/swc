#global private

// Cross-file (=> cross-Ast) inline of blockCopy/@memcpy from inside a METHOD that copies its own
// member array, exactly like Hash.Sha1.final:
//     Memory.copy(result, &.state[0], #sizeof(.state))
// The auto-member argument `&.state[0]` must resolve against the caller's receiver when the
// helper is inlined, and the full block must be copied.

struct CryptoState
{
    state: [5] u32
}

impl CryptoState
{
    mtd extract(result: [*] void)
    {
        InlineMem.blockCopy(result, &.state[0], #sizeof(.state))
    }
}

#test
{
    var h: CryptoState
    h.state[0] = 0x11111111
    h.state[1] = 0x22222222
    h.state[2] = 0x33333333
    h.state[3] = 0x44444444
    h.state[4] = 0x55555555

    var dst: [5] u32
    h.extract(&dst[0])

    @assert(dst[0] == 0x11111111)
    @assert(dst[1] == 0x22222222)
    @assert(dst[2] == 0x33333333)
    @assert(dst[3] == 0x44444444)
    @assert(dst[4] == 0x55555555)
}
