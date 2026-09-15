#global private

#[Swag.NoInline]
func floatBits32(value: f32)->u32
{
    var stored = value
    return (cast(const *u32) (&stored))[]
}

#[Swag.NoInline]
func floatBits64(value: f64)->u64
{
    var stored = value
    return (cast(const *u64) (&stored))[]
}

// Literal arguments must preserve the sign bit of zero through both the JIT
// and native calling conventions, even when positive zero is made in a register.
#test
{
    Swag.assert(floatBits32(0.0) == 0)
    Swag.assert(floatBits32(-0.0) == 0x8000_0000)
    Swag.assert(floatBits32(0.5) == 0x3F00_0000)
    Swag.assert(floatBits64(0.0) == 0)
    Swag.assert(floatBits64(-0.0) == 0x8000_0000_0000_0000)
    Swag.assert(floatBits64(0.5) == 0x3FE0_0000_0000_0000)
}
