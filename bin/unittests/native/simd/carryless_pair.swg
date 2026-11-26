#global private

alias Lanes  = [4] u64
alias Vector = #simd [2] u64

#[Swag.NoInline]
func foldWhileLive(vector: Vector, value: *Lanes, factor, addend: const *Lanes)->Vector
{
    Swag.vecCarrylessMul2XorPair(value, factor, addend, 0x00, 0x11)
    return vector
}

#test
{
    if not Swag.hasCpuFeature(.WideCarrylessMultiply)
    {
        return

    }
    let original: [4] u64 = [0xD2F90AFCEBCDB72E, 0x5AA7BD816AE61870, 0x2879276AAA66B2CE, 0xC810EFE2D3B76DF8]
    let factor:   [4] u64 = [0x2143357C7CA754EB, 0x806738A346614224, 0x658509CA1D213FAA, 0xA88F2375CF2552B3]
    let addend:   [4] u64 = [0xB82D840D503D37C6, 0x7BD75020C3001ADC, 0x53738262ACCE832A, 0x13074C82B4233510]
    let expected: [4] u64 = [0xC10350BB566EB944, 0x4C20FF50816CCF9E, 0x9798A7A88CDE2E8E, 0x67A1CDFB33AF6657]
    let aliased:  [4] u64 = [0xBAC1A497087F5346, 0x38EFED399CE4DCC3, 0x36684A3C049DD48C, 0xF0FCA16737994573]
    var result:   [4] u64

    var bytes: [33] u8
    let state = cast(*[4] u64, bytes.buffer + 1)
    Swag.memcpy(cast([*] void, state), cast(const [*] void, &original), 32)
    let vector = foldWhileLive(Swag.vecSplat(original[2]), state, &factor, &addend)
    Swag.memcpy(cast([*] void, &result), cast(const [*] void, state), 32)
    for i in 4
    {
        Swag.require(result[i] == expected[i])

    }
    result = original
    Swag.vecCarrylessMul2XorPair(&result, &factor, &result, 0x01, 0x10)
    for i in 4
    {
        Swag.require(result[i] == aliased[i])
    }
    Swag.require(vector[1] == original[2])

    // A factor range may overlap the destination, even when the addresses differ.
    var overlap:         [5] u64 = [0xC2B8FFCC938322BD, 0x0AA889DCCD456955, 0x6A7B903CC40FABC1, 0x4310614791132ED3, 0x93EB053466C0B193]
    let overlapExpected: [4] u64 = [0x022014A35306FAAA, 0x54D96FAC017679DD, 0x85D2B0F580EA03FC, 0x3007B0E8AE376AB9]
    let output                   = cast(*Lanes, overlap.buffer)
    let input                    = cast(const *Lanes, overlap.buffer + 1)
    Swag.vecCarrylessMul2XorPair(output, input, &addend, 0x10, 0x01)
    for i in 4
    {
        Swag.require(overlap[i] == overlapExpected[i])
    }
    Swag.require(overlap[4] == 0x93EB053466C0B193)
}
