#global private

// Operators the lanes cannot provide are rejected, not synthesized.
func mulBytes(a, b: #simd [16] u8)
{
    let c = a * b       // swc-expected-error {{sema_err_simd_operator}}
}

func divInts(a, b: #simd [4] s32)
{
    let c = a / b       // swc-expected-error {{sema_err_simd_operator}}
}

func modInts(a, b: #simd [4] s32)
{
    let c = a % b       // swc-expected-error {{sema_err_simd_operator}}
}

func shiftBytes(a: #simd [16] u8)
{
    let c = a << 1      // swc-expected-error {{sema_err_simd_operator}}
}

func sarWide(a: #simd [2] s64)
{
    let c = a >> 1      // swc-expected-error {{sema_err_simd_operator}}
}
