#global namespace Swag

// An optional instruction family that can be selected at runtime.
public enum CpuFeature: u32
{
    Aes = 1     // AES block rounds and round-key operations.
    CarrylessMultiply = 2     // Carry-less multiplication of polynomial coefficients.
    Sha = 4     // SHA-1 and SHA-256 compression instructions.
}

private
{
    func __x64CpuId(result: *[4] u32, leaf, subleaf: u32)

    const CpuFeaturesDetected = 1'u32 << 31
    var cpuFeatureBits: u32

    #[Swag.NoInline]
    func detectCpuFeatures()->u32
    {
        var registers: [4] u32
        Swag.__x64CpuId(&registers, 0, 0)
        let maxLeaf = registers[0]
        var bits    = CpuFeaturesDetected

        if maxLeaf >= 1
        {
            Swag.__x64CpuId(&registers, 1, 0)
            let ecx = registers[2]
            if ecx & (1'u32 << 25) do
                bits |= cast(u32, CpuFeature.Aes)
            if ecx & (1'u32 << 1) do
                bits |= cast(u32, CpuFeature.CarrylessMultiply)
        }

        if maxLeaf >= 7
        {
            Swag.__x64CpuId(&registers, 7, 0)
            if registers[1] & (1'u32 << 29) do
                bits |= cast(u32, CpuFeature.Sha)
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
