#global namespace Swag

// An optional instruction family that can be selected at runtime.
public enum CpuFeature: u32
{
    Aes = 1     // AES block rounds and round-key operations.
    CarrylessMultiply = 2     // Carry-less multiplication of polynomial coefficients.
    Sha = 4     // SHA-1 and SHA-256 compression instructions.
    WideCarrylessMultiply = 8     // 256-bit carry-less multiplication with independent 128-bit lanes.
    CarrylessMultiply512 = 16     // 512-bit carry-less multiplication with independent 128-bit lanes.
    MultiplyAdd52 = 32     // Packed 52-bit unsigned integer multiply-add.
}

private
{
    func __x64CpuId(result: *[4] u32, leaf, subleaf: u32)
    func __x64ReadXcr0()->u32

    const CpuFeaturesDetected = 1'u32 << 31
    const XsaveFlags = (1'u32 << 26) | (1'u32 << 27)

    // XCR0 must enable XMM, YMM, opmask and the upper ZMM register state.
    const Avx512State = 0xE6'u32
    var cpuFeatureBits: u32

    #[Swag.NoInline]
    func detectCpuFeatures()->u32
    {
        var registers: [4] u32
        Swag.__x64CpuId(&registers, 0, 0)
        let maxLeaf = registers[0]
        var bits    = CpuFeaturesDetected
        var osXsave = false

        if maxLeaf >= 1
        {
            Swag.__x64CpuId(&registers, 1, 0)
            let ecx = registers[2]
            osXsave = (ecx & XsaveFlags) == XsaveFlags
            if ecx & (1'u32 << 25) do
                bits |= cast(u32, CpuFeature.Aes)
            if ecx & (1'u32 << 1) do
                bits |= cast(u32, CpuFeature.CarrylessMultiply)
        }

        if maxLeaf >= 7
        {
            Swag.__x64CpuId(&registers, 7, 0)
            let ebx = registers[1]
            let ecx = registers[2]
            if ebx & (1'u32 << 29) do
                bits |= cast(u32, CpuFeature.Sha)

            let avx512Enabled = osXsave and (ebx & (1'u32 << 16)) != 0 and
                                (Swag.__x64ReadXcr0() & Avx512State) == Avx512State

            const MultiplyAddFeatures = (1'u32 << 21) | (1'u32 << 31)
            if avx512Enabled and (ebx & MultiplyAddFeatures) == MultiplyAddFeatures do
                bits |= cast(u32, CpuFeature.MultiplyAdd52)
            if ecx & (1'u32 << 10)
            {
                bits |= cast(u32, CpuFeature.WideCarrylessMultiply)
                if avx512Enabled do
                    bits |= cast(u32, CpuFeature.CarrylessMultiply512)
            }
        }

        Swag.atomicStore(&cpuFeatureBits, bits)
        return bits
    }
}

// Reports whether the executing CPU supports `feature`.
//
// Use this query before running instructions that require [[Swag.CpuFeature]].
// During compile-time execution it reports the compiler host's capabilities.
#[Swag.Inline]
public func hasCpuFeature(feature: CpuFeature)->bool
{
    var bits = Swag.atomicLoad(&cpuFeatureBits)
    if not bits do
        bits = detectCpuFeatures()
    return (bits & cast(u32, feature)) != 0
}
