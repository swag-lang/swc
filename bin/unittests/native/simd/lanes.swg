#global private

// Constant lane reads of register-resident vectors: lane zero of a 32- or
// 64-bit lane is one move out of the vector register, the other lanes slide
// there through a four-lane permute, and narrow lanes keep the memory path.
// Every read is checked against the array view of the same vector.

#[Swag.Optimize(true)]
func readU32Lanes(a, b: u32)->u64
{
    let v = cast(#simd [4] u32) [a, b, a + b, a ^ b]
    let w = v + Swag.vecsplat(1'u32)
    return cast(u64) w[0] + cast(u64) w[1] * 3 + cast(u64) w[2] * 5 + cast(u64) w[3] * 7
}

#[Swag.Optimize(true)]
func readS64Lanes(a, b: s64)->s64
{
    let v = cast(#simd [2] s64) [a, b]
    let w = v - Swag.vecsplat(2's64)
    return w[0] * 11 - w[1]
}

#[Swag.Optimize(true)]
func readF32Lanes(a, b: f32)->f32
{
    let v = cast(#simd [4] f32) [a, b, a * b, a - b]
    let w = v * Swag.vecsplat(2.0'f32)
    return w[0] + w[1] * 10 + w[2] * 100 + w[3] * 1000
}

#[Swag.Optimize(true)]
func readF64Lanes(a, b: f64)->f64
{
    let v = cast(#simd [2] f64) [a, b]
    let w = v + Swag.vecsplat(0.5'f64)
    return w[1] * 4 - w[0]
}

#[Swag.Optimize(true)]
func readU8Lanes(seed: u8)->u32
{
    let base: #simd [16] u8 = Swag.vecsplat(seed)
    let v = base + cast(#simd [16] u8) [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    return cast(u32) v[0] + cast(u32) v[9] * 256 + cast(u32) v[15] * 65536
}

#[Swag.Optimize(true)]
func lowLanesThroughBitcast(bytes: #simd [16] u8)->u64
{
    let low32  = (cast #bit(#simd [4] u32) bytes)[0]
    let low64  = (cast #bit(#simd [2] u64) bytes)[0]
    let high64 = (cast #bit(#simd [2] u64) bytes)[1]
    return cast(u64) low32 + low64 + high64
}

#test
{
    // (a+1) + 3(b+1) + 5(a+b+1) + 7((a^b)+1)
    Swag.assert(readU32Lanes(10, 20) == 11 + 63 + 155 + 7 * 31)
    Swag.assert(readS64Lanes(100, 7) == 98 * 11 - 5)
    Swag.assert(readF32Lanes(1.5, 2.0) == 3.0 + 40.0 + 600.0 - 1000.0)
    Swag.assert(readF64Lanes(1.0, 3.0) == 14.0 - 1.5)
    Swag.assert(readU8Lanes(3) == 3 + 12 * 256 + 18 * 65536)

    let bytes = cast(#simd [16] u8) [1'u8, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 4]
    Swag.assert(lowLanesThroughBitcast(bytes) == 1 + 0x0000_0002_0000_0001 + 0x0400_0000_0000_0003)
}
