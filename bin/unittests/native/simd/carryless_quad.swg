#global private

alias Lanes  = [8] u64
alias Vector = #simd [2] u64

#[Swag.NoInline]
func foldWhileLive(vector: Vector, value: *Lanes, factor, addend: const *Lanes)->Vector
{
    Swag.vecCarrylessMul2XorQuad(value, factor, addend, 0x00, 0x11)
    return vector
}

#test
{
    if not Swag.hasCpuFeature(.CarrylessMultiply512)
    {
        return

    }
    let original: Lanes = [
        0x71E273A87984A8AB, 0x9FB93534081C5253, 0xF93FE42EABD2D9F2, 0xDB149E4714BE09AB,
        0x5323451B4A95902A, 0x3994693EA3AE6E68, 0xA061AE14A1DBF721, 0x1AA615A94B6A5551
        ]
    let factor: Lanes = [
        0x5856C32A687B253B, 0x8B3A15353F137B70, 0x20DD5386C9CF0800, 0xA7213DFE89328293,
        0x919E9BC7F4A02D92, 0x67D1191FDA80A0BD, 0xB14CF51964CD1715, 0xFD95588C5E4EF10B
        ]
    let addend: Lanes = [
        0x344D04CB5F0F2C02, 0xD561CAB77E4D173D, 0x929E04E213311E91, 0x3C85B930B9F0920F,
        0xC5E1FB5BB643EDF4, 0x1B0B5A92CA9F1DAE, 0xF86C67B35A0AC810, 0xFECE6B989A323EAE
        ]
    let expected: Lanes = [
        0x18FE50ECF9D36EE7, 0x870C597A6FDC5F8D, 0x23175DC9BE560D5C, 0x5719FB94CA06269E,
        0x9796AE9AB36CF308, 0x3E3E665AE791D788, 0x9BFB598F704F92DE, 0xB9D6A0C25CA509B3
        ]
    let aliased: Lanes = [
        0xAB51A0B9DD10DC86, 0x8E9A5B8C328CBC46, 0xA230FF54372E69C4, 0xA16DDDE03EE5EC96,
        0xEDA464D85E2D1548, 0x39CDF5906CB0ECCC, 0x49B272C59C1B744F, 0x744F4C754BF88945
        ]
    var result: Lanes

    var bytes: [65] u8
    let state = cast(*Lanes, bytes.buffer + 1)
    Swag.memcpy(cast([*] void, state), cast(const [*] void, &original), 64)
    let vector = foldWhileLive(Swag.vecSplat(original[2]), state, &factor, &addend)
    Swag.memcpy(cast([*] void, &result), cast(const [*] void, state), 64)
    for i in 8
    {
        Swag.require(result[i] == expected[i])
    }
    Swag.require(vector[1] == original[2])

    result = original
    Swag.vecCarrylessMul2XorQuad(&result, &factor, &result, 0x01, 0x10)
    for i in 8
    {
        Swag.require(result[i] == aliased[i])
    }
}
